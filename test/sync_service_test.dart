import 'package:attendance_flow/models/attendance_models.dart';
import 'package:attendance_flow/services/attendance_store.dart';
import 'package:attendance_flow/services/auth_service.dart';
import 'package:attendance_flow/services/cloud_store.dart';
import 'package:attendance_flow/services/pro_service.dart';
import 'package:attendance_flow/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tracker _t(String id, String name, DateTime? at,
        Map<String, AttendanceStatus> days) =>
    Tracker(id: id, name: name, updatedAt: at, days: days);

class _FakeCloud implements CloudStore {
  CloudSnapshot snapshot = const CloudSnapshot(trackers: []);
  int pulls = 0;
  int pushes = 0;
  List<Tracker>? lastPushed;
  List<String> lastDeleted = [];

  @override
  Future<CloudSnapshot> pull(String uid) async {
    pulls++;
    return snapshot;
  }

  @override
  Future<void> push(
    String uid, {
    required List<Tracker> trackers,
    required String activeTrackerId,
    Iterable<String> deletedIds = const [],
  }) async {
    pushes++;
    lastPushed = trackers;
    lastDeleted = deletedIds.toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mergeTrackers', () {
    final older = DateTime.utc(2026, 9, 1);
    final newer = DateTime.utc(2026, 9, 20);

    test('newest edit wins per calendar', () {
      final local = [
        _t('a', 'Local', older, {'2026-9-1': AttendanceStatus.present})
      ];
      final cloud = [
        _t('a', 'Cloud', newer, {'2026-9-2': AttendanceStatus.late})
      ];
      final merged = SyncService.mergeTrackers(local: local, cloud: cloud);
      expect(merged.single.name, 'Cloud');
      expect(merged.single.days.keys, ['2026-9-2']);
    });

    test('local wins when it is newer or both are untimed', () {
      final merged = SyncService.mergeTrackers(
        local: [
          _t('a', 'Local', newer, {}),
          _t('b', 'Untimed local', null, {})
        ],
        cloud: [
          _t('a', 'Cloud', older, {}),
          _t('b', 'Untimed cloud', null, {})
        ],
      );
      expect(merged.map((t) => t.name), ['Local', 'Untimed local']);
    });

    test('cloud-only calendars come down, local-only stay', () {
      final merged = SyncService.mergeTrackers(
        local: [_t('l', 'Only here', older, {})],
        cloud: [_t('c', 'Only cloud', older, {})],
      );
      expect(merged.map((t) => t.id), ['l', 'c']);
    });

    test('locally deleted calendars are not resurrected', () {
      final merged = SyncService.mergeTrackers(
        local: [_t('keep', 'Keep', older, {})],
        cloud: [_t('gone', 'Gone', newer, {}), _t('keep', 'Keep', older, {})],
        locallyDeleted: {'gone'},
      );
      expect(merged.map((t) => t.id), ['keep']);
    });
  });

  group('SyncService gating', () {
    test('does nothing for free users or when signed out', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AttendanceStore();
      await store.load();
      final auth = AuthService(enableFirebase: false);
      await auth.init();
      final pro = ProService(enableStore: false, auth: auth);
      await pro.init();
      final cloud = _FakeCloud();
      final sync =
          SyncService(store: store, auth: auth, pro: pro, cloud: cloud);
      sync.init();
      await sync.syncNow();
      await store.togglePresent(DateTime(2026, 9, 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sync.isActive, isFalse);
      expect(cloud.pulls, 0);
      expect(cloud.pushes, 0);
      sync.dispose();
    });
  });

  group('deleteTracker', () {
    test('records pending deletes for the sync layer', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AttendanceStore();
      await store.load();
      await store.addTracker('Gym', isPro: true);
      final gymId = store.activeId;
      await store.deleteTracker(gymId);
      expect(store.pendingDeletes, {gymId});
      expect(store.trackers.any((t) => t.id == gymId), isFalse);
    });
  });
}
