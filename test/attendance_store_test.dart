import 'package:attendance_flow/models/attendance_models.dart';
import 'package:attendance_flow/services/attendance_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates legacy present days into the default tracker', () async {
    SharedPreferences.setMockInitialValues({
      'attendance_data': '{"2026-8":["2026-8-2","2026-8-5"]}',
      'start_month': '2026-8',
    });
    final store = AttendanceStore();
    await store.load();
    expect(store.trackers, hasLength(1));
    expect(store.active.name, 'Attendance');
    expect(
        store.active.statusOn(DateTime(2026, 8, 2)), AttendanceStatus.present);
    expect(store.active.startMonth, DateTime(2026, 8));
  });

  test('free tier cannot add a second calendar', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AttendanceStore();
    await store.load();
    final added = await store.addTracker('Gym', isPro: false);
    expect(added, isFalse);
    expect(store.trackers, hasLength(1));
  });

  test('pro can add a second calendar', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AttendanceStore();
    await store.load();
    final added = await store.addTracker('Gym', isPro: true);
    expect(added, isTrue);
    expect(store.trackers, hasLength(2));
    expect(store.active.name, 'Gym');
  });

  test('export csv lists marked days', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AttendanceStore();
    await store.load();
    await store.setStatus(DateTime(2026, 8, 3), AttendanceStatus.present);
    final csv = store.exportCsv();
    expect(csv, contains('date,status'));
    expect(csv, contains('2026-8-3,present'));
  });

  test('corrupt local data still loads a default calendar', () async {
    SharedPreferences.setMockInitialValues({
      'attendance_v2': '{not-json',
    });
    final store = AttendanceStore();
    await store.load();
    expect(store.trackers, hasLength(1));
    expect(store.active.name, 'Attendance');
  });
}
