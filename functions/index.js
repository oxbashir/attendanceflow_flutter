// Attendance Flow — Cloud Functions (2nd gen, Node 20).
//
//  syncSubscription  callable  Verify a Play subscription token with the
//                              Google Play Developer API and store the
//                              entitlement on the caller's account.
//  deleteAccount     callable  Remove all cloud data and the Auth user.
//  onPlayNotification pub/sub  Real-time developer notifications from Play
//                              (renewals, cancellations, expiries) keep the
//                              stored entitlement current.
//
// The functions' default service account must be granted access in Play
// Console (Users and permissions → invite <project-id>@appspot.gserviceaccount.com
// with "View financial data" + "Manage orders and subscriptions"), and the
// "Google Play Android Developer API" must be enabled on the project.

import { createHash } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { logger } from 'firebase-functions';
import { google } from 'googleapis';

initializeApp();

const REGION = 'europe-west1';
const PACKAGE_NAME = 'com.attendance_flow.myapp';
const SUBSCRIPTION_ID = 'attendance_flow_pro';
const RTDN_TOPIC = 'play-rtdn';

const db = getFirestore();

// States in which the user still has access. CANCELED means auto-renew is
// off but the paid period has not ended yet.
const ACCESS_STATES = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);

let publisherClient;
async function publisher() {
  if (!publisherClient) {
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });
    publisherClient = google.androidpublisher({ version: 'v3', auth });
  }
  return publisherClient;
}

function tokenId(token) {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Ask Play about one purchase token.
 * @returns {{active: boolean, state: string, expiryTimeMillis: number|null,
 *            autoRenewing: boolean, productId: string|null}}
 */
async function verifyToken(token) {
  const api = await publisher();
  const { data } = await api.purchases.subscriptionsv2.get({
    packageName: PACKAGE_NAME,
    token,
  });

  const state = data.subscriptionState ?? 'SUBSCRIPTION_STATE_UNSPECIFIED';
  const items = data.lineItems ?? [];
  const item = items.find((li) => li.productId === SUBSCRIPTION_ID) ?? items[0];
  const expiryMillis = item?.expiryTime ? Date.parse(item.expiryTime) : null;
  const notExpired = expiryMillis == null ? true : expiryMillis > Date.now();
  const rightProduct = item?.productId === SUBSCRIPTION_ID;

  return {
    active: rightProduct && ACCESS_STATES.has(state) && notExpired,
    state,
    expiryTimeMillis: expiryMillis,
    autoRenewing: Boolean(item?.autoRenewingPlan?.autoRenewEnabled),
    productId: item?.productId ?? null,
    acknowledgementState: data.acknowledgementState ?? null,
  };
}

/**
 * Verify and persist the entitlement for `uid`. Returns the client payload.
 */
async function syncFor(uid, providedToken) {
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  const stored = snap.exists ? snap.get('pro') ?? {} : {};

  const token = providedToken ?? stored.purchaseToken ?? null;
  if (!token) {
    const none = { active: false, state: 'NO_TOKEN', expiryTimeMillis: null, autoRenewing: false };
    await userRef.set({ pro: { ...none, updatedAt: FieldValue.serverTimestamp() } }, { merge: true });
    return none;
  }

  // A purchase token belongs to exactly one account.
  const tokenRef = db.collection('purchaseTokens').doc(tokenId(token));
  const tokenSnap = await tokenRef.get();
  if (tokenSnap.exists && tokenSnap.get('uid') !== uid) {
    throw new HttpsError(
      'already-exists',
      'This Google Play subscription is already linked to another account.',
    );
  }

  let result;
  try {
    result = await verifyToken(token);
  } catch (err) {
    logger.error('Play verification failed', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Could not verify the subscription with Google Play.');
  }

  const pro = {
    active: result.active,
    state: result.state,
    expiryTimeMillis: result.expiryTimeMillis,
    autoRenewing: result.autoRenewing,
    productId: result.productId,
    purchaseToken: token,
    updatedAt: FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(userRef, { pro }, { merge: true });
  batch.set(tokenRef, { uid, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await batch.commit();

  // Acknowledge if the client failed to (Play refunds unacknowledged
  // subscriptions after 3 days).
  if (result.active && result.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING') {
    try {
      const api = await publisher();
      await api.purchases.subscriptions.acknowledge({
        packageName: PACKAGE_NAME,
        subscriptionId: SUBSCRIPTION_ID,
        token,
      });
    } catch (err) {
      logger.warn('Acknowledge failed', { uid, err: String(err) });
    }
  }

  return {
    active: result.active,
    state: result.state,
    expiryTimeMillis: result.expiryTimeMillis,
    autoRenewing: result.autoRenewing,
  };
}

export const syncSubscription = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');

    const token = request.data?.purchaseToken;
    if (token != null && (typeof token !== 'string' || token.length > 4096)) {
      throw new HttpsError('invalid-argument', 'Bad purchase token.');
    }
    return syncFor(uid, token ?? null);
  },
);

export const deleteAccount = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');

  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  const token = snap.exists ? snap.get('pro.purchaseToken') : null;

  await db.recursiveDelete(userRef);
  if (token) {
    await db.collection('purchaseTokens').doc(tokenId(token)).delete().catch(() => {});
  }
  await getAuth().deleteUser(uid);
  logger.info('Account deleted', { uid });
  return { ok: true };
});

// Play → Pub/Sub → here. Set the topic in Play Console → Monetization setup.
export const onPlayNotification = onMessagePublished(
  { region: REGION, topic: RTDN_TOPIC },
  async (event) => {
    const payload = event.data.message.json;
    const note = payload?.subscriptionNotification;
    if (!note?.purchaseToken) {
      logger.debug('Ignoring non-subscription RTDN', payload);
      return;
    }
    const tokenSnap = await db.collection('purchaseTokens').doc(tokenId(note.purchaseToken)).get();
    if (!tokenSnap.exists) {
      logger.info('RTDN for unlinked token; will link when the user signs in');
      return;
    }
    const uid = tokenSnap.get('uid');
    try {
      await syncFor(uid, note.purchaseToken);
      logger.info('Entitlement refreshed from RTDN', { uid, type: note.notificationType });
    } catch (err) {
      logger.error('RTDN sync failed', { uid, err: String(err) });
    }
  },
);
