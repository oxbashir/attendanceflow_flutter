import 'dart:convert';
import 'dart:io';

import 'package:attendance_flow/screens/HomeScreen.dart';
import 'package:attendance_flow/services/app_update_service.dart';
import 'package:attendance_flow/services/attendance_store.dart';
import 'package:attendance_flow/services/pro_service.dart';
import 'package:attendance_flow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phoneSize = Size(1080, 1920);

  Future<void> configurePhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = 1.0;
  }

  const screenshotKey = Key('play_store_screenshot');

  Future<void> pumpHomeScreen(WidgetTester tester) async {
    await configurePhoneSurface(tester);
    final store = AttendanceStore();
    await store.load();
    final pro = ProService(enableStore: false);
    await pro.init();
    final updates = AppUpdateService(enableStore: false);
    await updates.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: SizedBox(
          key: screenshotKey,
          width: phoneSize.width,
          height: phoneSize.height,
          child: AttendanceStoreScope(
            store: store,
            child: ProScope(
              service: pro,
              child: AppUpdateScope(
                service: updates,
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  group('Play Store screenshots', () {
    setUp(() {
      final now = DateTime.now();
      final monthKey = '${now.year}-${now.month}';
      SharedPreferences.setMockInitialValues({
        'attendance_data': jsonEncode({
          monthKey: [
            '${now.year}-${now.month}-2',
            '${now.year}-${now.month}-3',
            '${now.year}-${now.month}-5',
            '${now.year}-${now.month}-8',
            '${now.year}-${now.month}-10',
            '${now.year}-${now.month}-12',
            '${now.year}-${now.month}-15',
            '${now.year}-${now.month}-18',
          ],
        }),
        'start_month': '${now.year}-${now.month}',
      });
    });

    testWidgets('phone_01_calendar', (tester) async {
      await pumpHomeScreen(tester);
      await expectLater(
        find.byKey(screenshotKey),
        matchesGoldenFile('goldens/phone_01_calendar.png'),
      );
    });

    testWidgets('phone_02_edit_mode', (tester) async {
      await pumpHomeScreen(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(screenshotKey),
        matchesGoldenFile('goldens/phone_02_edit_mode.png'),
      );
    });

    testWidgets('phone_03_stats', (tester) async {
      await pumpHomeScreen(tester);
      await expectLater(
        find.byKey(screenshotKey),
        matchesGoldenFile('goldens/phone_03_stats.png'),
      );
    });

    testWidgets('phone_04_next_month', (tester) async {
      await pumpHomeScreen(tester);
      await tester.tap(find.byKey(const Key('next_month')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(screenshotKey),
        matchesGoldenFile('goldens/phone_04_next_month.png'),
      );
    });
  });

  tearDownAll(() {
    final goldensDir = Directory('test/goldens');
    final outputDir = Directory('store-assets/screenshots');
    if (!goldensDir.existsSync()) return;

    outputDir.createSync(recursive: true);
    for (final file in goldensDir.listSync().whereType<File>()) {
      if (file.path.endsWith('.png')) {
        final target = File('${outputDir.path}/${file.uri.pathSegments.last}');
        if (target.existsSync()) target.deleteSync();
        file.copySync(target.path);
      }
    }
  });
}
