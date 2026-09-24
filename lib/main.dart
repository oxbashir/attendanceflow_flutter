import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'screens/HomeScreen.dart';
import 'services/app_update_service.dart';
import 'services/attendance_store.dart';
import 'services/auth_service.dart';
import 'services/cloud_store.dart';
import 'services/entitlement_backend.dart';
import 'services/pro_service.dart';
import 'services/sync_service.dart';
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
  final auth = AuthService();
  // Accounts only exist once Firebase is configured; otherwise Pro keeps
  // working device-only exactly as before.
  final cloudReady = DefaultFirebaseOptions.isConfigured;
  final pro = ProService(
    auth: auth,
    backend: cloudReady ? FirebaseEntitlementBackend() : null,
  );
  final updates = AppUpdateService();
  final sync = SyncService(
    store: store,
    auth: auth,
    pro: pro,
    cloud: cloudReady ? FirestoreCloudStore() : null,
  );

  try {
    await themeController.load();
  } catch (_) {}
  try {
    await store.load();
  } catch (_) {}

  // Play Billing, Firebase, and in-app updates can hang on review devices.
  // Never block first frame.
  unawaited(auth.init().then((_) => pro.init()).then((_) => sync.init()));
  unawaited(updates.init());

  runApp(
    MyApp(
      themeController: themeController,
      store: store,
      pro: pro,
      updates: updates,
      auth: auth,
      sync: sync,
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
    this.auth,
    this.sync,
  });

  final ThemeController themeController;
  final AttendanceStore store;
  final ProService pro;
  final AppUpdateService updates;
  final AuthService? auth;
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    Widget app = ListenableBuilder(
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
    );
    if (sync != null) app = SyncScope(service: sync!, child: app);
    if (auth != null) app = AuthScope(service: auth!, child: app);
    return ThemeScope(
      controller: themeController,
      child: AttendanceStoreScope(
        store: store,
        child: ProScope(
          service: pro,
          child: AppUpdateScope(service: updates, child: app),
        ),
      ),
    );
  }
}
