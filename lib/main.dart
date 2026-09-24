import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/HomeScreen.dart';
import 'services/app_update_service.dart';
import 'services/attendance_store.dart';
import 'services/pro_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
    ErrorWidget.builder = (details) {
      return const ColoredBox(color: Color(0xFFF8F7F4));
    };
  }

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final themeController = ThemeController();
  final store = AttendanceStore();
  final pro = ProService();
  final updates = AppUpdateService();

  try {
    await themeController.load();
  } catch (_) {}
  try {
    await store.load();
  } catch (_) {}

  // Play Billing and in-app updates can hang on review devices. Never block first frame.
  unawaited(pro.init());
  unawaited(updates.init());

  runApp(
    MyApp(
      themeController: themeController,
      store: store,
      pro: pro,
      updates: updates,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.themeController,
    required this.store,
    required this.pro,
    required this.updates,
  });

  final ThemeController themeController;
  final AttendanceStore store;
  final ProService pro;
  final AppUpdateService updates;

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: themeController,
      child: AttendanceStoreScope(
        store: store,
        child: ProScope(
          service: pro,
          child: AppUpdateScope(
            service: updates,
            child: ListenableBuilder(
              listenable: themeController,
              builder: (context, _) {
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: 'Attendance',
                  theme: AppTheme.light,
                  darkTheme: AppTheme.dark,
                  themeMode: themeController.mode,
                  themeAnimationDuration: const Duration(milliseconds: 320),
                  themeAnimationCurve: Curves.easeInOutCubic,
                  home: const HomeScreen(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
