import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance_models.dart';

/// What the cloud holds for one account.
class CloudSnapshot {
  const CloudSnapshot({required this.trackers, this.activeTrackerId});

  final List<Tracker> trackers;
  final String? activeTrackerId;
}

/// Storage for a Pro user's calendars. Abstract so the merge logic can be
/// unit-tested without Firestore.
abstract class CloudStore {
  Future<CloudSnapshot> pull(String uid);

  Future<void> push(
    String uid, {
    required List<Tracker> trackers,
    required String activeTrackerId,
    Iterable<String> deletedIds = const [],
  });
}

class FirestoreCloudStore implements CloudStore {
  FirestoreCloudStore([FirebaseFirestore? db]) : _injected = db;

  final FirebaseFirestore? _injected;

  // Resolve on first use so `main` can construct this before
  // `Firebase.initializeApp()` (which runs in AuthService.init).
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _trackers(String uid) =>
      _user(uid).collection('trackers');

  @override
  Future<CloudSnapshot> pull(String uid) async {
    final results = await Future.wait([
      _user(uid).get(const GetOptions(source: Source.server)),
      _trackers(uid).get(const GetOptions(source: Source.server)),
    ]);
    final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final trackerDocs = results[1] as QuerySnapshot<Map<String, dynamic>>;

    final trackers = <Tracker>[];
    for (final doc in trackerDocs.docs) {
      final data = doc.data();
      if (data['deleted'] == true) continue;
      final json = <String, dynamic>{
        'id': doc.id,
        'name': data['name'],
        'startMonth': data['startMonth'],
        'days': data['days'],
      };
      final updated = data['updatedAt'];
      if (updated is Timestamp) {
        json['updatedAt'] = updated.toDate().toUtc().toIso8601String();
      } else if (updated is String) {
        json['updatedAt'] = updated;
      }
      trackers.add(Tracker.fromJson(json));
    }
    return CloudSnapshot(
      trackers: trackers,
      activeTrackerId: userDoc.data()?['activeTrackerId'] as String?,
    );
  }

  @override
  Future<void> push(
    String uid, {
    required List<Tracker> trackers,
    required String activeTrackerId,
    Iterable<String> deletedIds = const [],
  }) async {
    final batch = _db.batch();
    batch.set(
      _user(uid),
      {
        'activeTrackerId': activeTrackerId,
        'lastSyncAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    for (final t in trackers) {
      final json = t.toJson();
      batch.set(_trackers(uid).doc(t.id), {
        'name': json['name'],
        'startMonth': json['startMonth'],
        'days': json['days'],
        'updatedAt': t.updatedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(t.updatedAt!),
        'deleted': false,
      });
    }
    for (final id in deletedIds) {
      // Tombstone rather than delete so an older device cannot resurrect it.
      batch.set(
          _trackers(uid).doc(id),
          {
            'deleted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    await batch.commit();
  }
}
