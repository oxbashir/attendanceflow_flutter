import 'dart:async';

import 'package:flutter/material.dart';

import '../models/attendance_models.dart';
import 'attendance_store.dart';
import 'auth_service.dart';
import 'cloud_store.dart';
import 'pro_service.dart';

/// Keeps a Pro user's calendars in the cloud so they survive reinstalls and
/// device changes. Free users are never touched: the local store stays the
/// only copy until someone signs in and Pro is active.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.store,
    required this.auth,
    required this.pro,
    CloudStore? cloud,
  }) : _cloud = cloud;

  final AttendanceStore store;
  final AuthService auth;
  final ProService pro;
  final CloudStore? _cloud;

  static const _debounce = Duration(milliseconds: 1500);

  bool syncing = false;
  DateTime? lastSyncedAt;
  String? lastError;

  bool _listening = false;
  bool _hydrated = false;
  String? _hydratedUid;
  Timer? _pushTimer;

  /// True when this device is allowed to sync right now.
  bool get isActive =>
      _cloud != null && auth.enabled && auth.isSignedIn && pro.isPro;

  void init() {
    if (_listening) return;
    _listening = true;
    auth.addListener(_onGate);
    pro.addListener(_onGate);
    store.addListener(_onStoreChanged);
    _onGate();
  }

  void _onGate() {
    if (!isActive) {
      if (_hydratedUid != auth.uid) {
        _hydrated = false;
        _hydratedUid = null;
      }
      return;
    }
    if (!_hydrated || _hydratedUid != auth.uid) {
      unawaited(syncNow());
    }
  }

  void _onStoreChanged() {
    if (!isActive || !_hydrated) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_debounce, () => unawaited(_push()));
  }

  /// Pull, merge, then push. Safe to call any time; no-op when inactive.
  Future<void> syncNow() async {
    if (!isActive || syncing) return;
    final uid = auth.uid!;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      final cloud = await _cloud!.pull(uid);
      final merged = mergeTrackers(
        local: store.trackers,
        cloud: cloud.trackers,
        locallyDeleted: store.pendingDeletes,
      );
      final changed = !_sameContent(store.trackers, merged);
      if (changed) {
        await store.applyMerged(
          merged,
          preferredActive: store.trackers.any((t) => t.id == store.activeId)
              ? store.activeId
              : cloud.activeTrackerId,
        );
      }
      _hydrated = true;
      _hydratedUid = uid;
      await _push();
    } catch (e) {
      debugPrint('Sync failed: $e');
      lastError = 'Could not sync with your account.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    if (!isActive || !_hydrated) return;
    final uid = auth.uid!;
    final deleted = store.pendingDeletes.toList();
    try {
      await _cloud!.push(
        uid,
        trackers: store.trackers,
        activeTrackerId: store.activeId,
        deletedIds: deleted,
      );
      store.pendingDeletes.removeAll(deleted);
      lastSyncedAt = DateTime.now();
      lastError = null;
    } catch (e) {
      debugPrint('Push failed: $e');
      lastError = 'Could not sync with your account.';
    }
    notifyListeners();
  }

  /// Newest edit wins per calendar. Calendars deleted here stay deleted;
  /// calendars only in the cloud come down; calendars only here go up.
  @visibleForTesting
  static List<Tracker> mergeTrackers({
    required List<Tracker> local,
    required List<Tracker> cloud,
    Set<String> locallyDeleted = const {},
  }) {
    final byId = <String, Tracker>{};
    for (final t in local) {
      byId[t.id] = t;
    }
    for (final c in cloud) {
      if (locallyDeleted.contains(c.id)) continue;
      final l = byId[c.id];
      if (l == null) {
        byId[c.id] = c;
        continue;
      }
      final lTime = l.updatedAt;
      final cTime = c.updatedAt;
      if (lTime == null && cTime != null) {
        byId[c.id] = c;
      } else if (lTime != null && cTime != null && cTime.isAfter(lTime)) {
        byId[c.id] = c;
      }
      // Otherwise keep local (newer, or both untimed).
    }
    // Keep local ordering first, then cloud-only ones in cloud order.
    final ordered = <Tracker>[
      for (final t in local)
        if (byId.containsKey(t.id)) byId[t.id]!,
      for (final c in cloud)
        if (byId.containsKey(c.id) && !local.any((t) => t.id == c.id))
          byId[c.id]!,
    ];
    return ordered;
  }

  static bool _sameContent(List<Tracker> a, List<Tracker> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id || x.name != y.name) return false;
      if (x.updatedAt != y.updatedAt) return false;
      if (x.days.length != y.days.length) return false;
      for (final e in x.days.entries) {
        if (y.days[e.key] != e.value) return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    if (_listening) {
      auth.removeListener(_onGate);
      pro.removeListener(_onGate);
      store.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}

class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({
    super.key,
    required SyncService service,
    required super.child,
  }) : super(notifier: service);

  static SyncService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SyncScope>()?.notifier;
  }
}
