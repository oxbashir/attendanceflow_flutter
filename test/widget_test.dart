import 'package:attendance_flow/main.dart';
import 'package:attendance_flow/services/app_update_service.dart';
import 'package:attendance_flow/services/attendance_store.dart';
import 'package:attendance_flow/services/pro_service.dart';
import 'package:attendance_flow/theme/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the default calendar', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AttendanceStore();
    await store.load();
    final pro = ProService(enableStore: false);
    await pro.init();
    final updates = AppUpdateService(enableStore: false);
    await updates.init();

    await tester.pumpWidget(
      MyApp(
        themeController: ThemeController(),
        store: store,
        pro: pro,
        updates: updates,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attendance'), findsWidgets);
  });
}
