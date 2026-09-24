import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_models.dart';

class AttendanceStore extends ChangeNotifier {
  static const _v2Key = 'attendance_v2';
  static const _legacyDataKey = 'attendance_data';
  static const _legacyStartKey = 'start_month';
  static const defaultTrackerId = 'default';

  final List<Tracker> trackers = [];
  String activeId = defaultTrackerId;

  Tracker get active {
    for (final t in trackers) {
      if (t.id == activeId) return t;
    }
    _ensureDefault();
    return trackers.first;
  }

  void _ensureDefault() {
    if (trackers.isEmpty) {
      trackers.add(Tracker(id: defaultTrackerId, name: 'Attendance'));
      activeId = defaultTrackerId;
    } else if (!trackers.any((t) => t.id == activeId)) {
      activeId = trackers.first.id;
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v2 = prefs.getString(_v2Key);
      if (v2 != null) {
        _readV2(v2);
      } else {
        _migrateLegacy(prefs);
      }
    } catch (_) {
      trackers.clear();
    }
    _ensureDefault();
    notifyListeners();
    try {
      await save();
    } catch (_) {}
  }

  void _readV2(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    activeId = decoded['activeTrackerId'] as String? ?? defaultTrackerId;
    final list = decoded['trackers'] as List<dynamic>? ?? [];
    trackers
      ..clear()
      ..addAll(
        list.map((e) => Tracker.fromJson(e as Map<String, dynamic>)),
      );
  }

  void _migrateLegacy(SharedPreferences prefs) {
    final raw = prefs.getString(_legacyDataKey);
    final days = <String, AttendanceStatus>{};
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((_, value) {
        if (value is! List) return;
        for (final s in value) {
          days[s.toString()] = AttendanceStatus.present;
        }
      });
    }
    DateTime? start;
    final sm = prefs.getString(_legacyStartKey);
    if (sm != null) {
      final p = sm.split('-');
      if (p.length >= 2) {
        start = DateTime(int.parse(p[0]), int.parse(p[1]));
      }
    }
    trackers
      ..clear()
      ..add(
        Tracker(
          id: defaultTrackerId,
          name: 'Attendance',
          startMonth: start,
          days: days,
        ),
      );
    activeId = defaultTrackerId;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _v2Key,
      jsonEncode({
        'version': 2,
        'activeTrackerId': activeId,
        'trackers': trackers.map((t) => t.toJson()).toList(),
      }),
    );
  }

  void select(String id) {
    if (!trackers.any((t) => t.id == id)) return;
    activeId = id;
    notifyListeners();
    save();
  }

  /// Ids of calendars deleted locally since the last cloud sync. The sync
  /// layer drains this so the deletion propagates instead of being undone by
  /// the next pull.
  final Set<String> pendingDeletes = {};

  Future<bool> addTracker(String name, {required bool isPro}) async {
    if (!isPro && trackers.isNotEmpty) return false;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    trackers.add(
      Tracker(id: id, name: name.trim().isEmpty ? 'Calendar' : name.trim())
        ..touch(),
    );
    activeId = id;
    notifyListeners();
    await save();
    return true;
  }

  Future<void> renameTracker(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    for (final t in trackers) {
      if (t.id == id) {
        t.name = trimmed;
        t.touch();
      }
    }
    notifyListeners();
    await save();
  }

  Future<void> deleteTracker(String id) async {
    if (trackers.length <= 1) return;
    trackers.removeWhere((t) => t.id == id);
    pendingDeletes.add(id);
    if (activeId == id) activeId = trackers.first.id;
    notifyListeners();
    await save();
  }

  /// Replaces the local calendars with the outcome of a cloud merge.
  /// Does not touch [pendingDeletes]; the caller owns that lifecycle.
  Future<void> applyMerged(List<Tracker> merged,
      {String? preferredActive}) async {
    trackers
      ..clear()
      ..addAll(merged);
    if (preferredActive != null &&
        trackers.any((t) => t.id == preferredActive)) {
      activeId = preferredActive;
    }
    _ensureDefault();
    notifyListeners();
    await save();
  }

  void _ensureStart(Tracker tracker, DateTime date) {
    tracker.startMonth ??= DateTime(date.year, date.month);
  }

  Future<void> togglePresent(DateTime date) async {
    final tracker = active;
    _ensureStart(tracker, date);
    final key = Tracker.dayKey(date);
    final current = tracker.days[key];
    if (current == null) {
      tracker.days[key] = AttendanceStatus.present;
    } else {
      tracker.days.remove(key);
    }
    tracker.touch();
    notifyListeners();
    await save();
  }

  Future<void> setStatus(DateTime date, AttendanceStatus? status) async {
    final tracker = active;
    _ensureStart(tracker, date);
    final key = Tracker.dayKey(date);
    if (status == null) {
      tracker.days.remove(key);
    } else {
      tracker.days[key] = status;
    }
    tracker.touch();
    notifyListeners();
    await save();
  }

  String exportCsv({Tracker? tracker}) {
    final t = tracker ?? active;
    final entries = t.days.entries.toList()
      ..sort((a, b) => _parseDay(a.key).compareTo(_parseDay(b.key)));
    final buf = StringBuffer('date,status\n');
    for (final e in entries) {
      buf.writeln('${e.key},${e.value.storage}');
    }
    return buf.toString();
  }

  String exportBackupJson() {
    return jsonEncode({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'activeTrackerId': activeId,
      'trackers': trackers.map((t) => t.toJson()).toList(),
    });
  }

  Future<void> restoreBackupJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not an Attendance Flow backup.');
    }
    final list = decoded['trackers'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('Backup has no calendars.');
    }
    trackers
      ..clear()
      ..addAll(
        list.map((e) => Tracker.fromJson(e as Map<String, dynamic>)..touch()),
      );
    activeId = decoded['activeTrackerId'] as String? ?? trackers.first.id;
    if (!trackers.any((t) => t.id == activeId)) {
      activeId = trackers.first.id;
    }
    notifyListeners();
    await save();
  }

  DateTime _parseDay(String key) {
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

class AttendanceStoreScope extends InheritedNotifier<AttendanceStore> {
  const AttendanceStoreScope({
    super.key,
    required AttendanceStore store,
    required super.child,
  }) : super(notifier: store);

  static AttendanceStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AttendanceStoreScope>()
        ?.notifier;
  }
}
