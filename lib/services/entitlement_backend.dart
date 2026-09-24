import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../config/account_config.dart';

/// Server-side view of the Pro subscription for the signed-in account.
class EntitlementStatus {
  const EntitlementStatus({
    required this.active,
    this.expiresAt,
    this.state,
    this.autoRenewing = false,
  });

  final bool active;
  final DateTime? expiresAt;

  /// Play `subscriptionState`, e.g. SUBSCRIPTION_STATE_ACTIVE.
  final String? state;
  final bool autoRenewing;

  static const none = EntitlementStatus(active: false);

  factory EntitlementStatus.fromMap(Map<String, dynamic>? map) {
    if (map == null) return none;
    final expiry = map['expiryTimeMillis'];
    return EntitlementStatus(
      active: map['active'] == true,
      expiresAt: expiry is num
          ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt(), isUtc: true)
          : null,
      state: map['state'] as String?,
      autoRenewing: map['autoRenewing'] == true,
    );
  }
}

/// Talks to the backend that verifies Play purchases and stores the result on
/// the user's account. Abstract so tests can swap in a fake.
abstract class EntitlementBackend {
  /// Asks the server to (re)verify the subscription for the current user.
  /// [purchaseToken] links a fresh Play purchase to the account; when null the
  /// server re-checks whatever token it already has.
  Future<EntitlementStatus> sync({String? purchaseToken});

  /// Live updates of the stored entitlement (fed by Play real-time
  /// developer notifications on the server).
  Stream<EntitlementStatus> watch(String uid);
}

class FirebaseEntitlementBackend implements EntitlementBackend {
  FirebaseEntitlementBackend();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: AccountConfig.functionsRegion);

  @override
  Future<EntitlementStatus> sync({String? purchaseToken}) async {
    final result = await _functions
        .httpsCallable('syncSubscription')
        .call<Map<String, dynamic>>({
      if (purchaseToken != null) 'purchaseToken': purchaseToken,
      'packageName': AccountConfig.packageName,
    }).timeout(const Duration(seconds: 25));
    return EntitlementStatus.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  @override
  Stream<EntitlementStatus> watch(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) {
      final data = snap.data();
      final pro = data?['pro'];
      return EntitlementStatus.fromMap(
        pro is Map ? Map<String, dynamic>.from(pro) : null,
      );
    });
  }
}
