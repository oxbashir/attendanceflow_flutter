import 'dart:async';

import 'package:attendance_flow/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway implements AppUpdateGateway {
  AppUpdateCheckResult result = const AppUpdateCheckResult(available: false);
  AppUpdateFlowOutcome flexible = AppUpdateFlowOutcome.success;
  int openStoreCount = 0;
  int completeCount = 0;
  final controller = StreamController<AppUpdateInstallEvent>.broadcast();

  @override
  Future<AppUpdateCheckResult> check() async => result;

  @override
  Future<AppUpdateFlowOutcome> startFlexible() async => flexible;

  @override
  Future<AppUpdateFlowOutcome> startImmediate() async =>
      AppUpdateFlowOutcome.failed;

  @override
  Future<void> complete() async {
    completeCount++;
  }

  @override
  Future<void> openStore() async {
    openStoreCount++;
  }

  @override
  Stream<AppUpdateInstallEvent> get events => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('disabled store stays idle', () async {
    final service = AppUpdateService(enableStore: false);
    await service.init();
    expect(service.updateAvailable, isFalse);
    expect(service.showBanner, isFalse);
    expect(await service.handleUserTap(), "You're on the latest version.");
  });

  test('available update shows a banner', () async {
    final gateway = _FakeGateway()
      ..result = const AppUpdateCheckResult(
        available: true,
        flexibleAllowed: true,
        versionCode: 12,
      );
    final service = AppUpdateService(gateway: gateway);
    await service.init();
    expect(service.updateAvailable, isTrue);
    expect(service.showBanner, isTrue);
    expect(service.actionLabel, 'Update available');
  });

  test('dismissing the banner hides it until a newer code', () async {
    final gateway = _FakeGateway()
      ..result = const AppUpdateCheckResult(
        available: true,
        flexibleAllowed: true,
        versionCode: 12,
      );
    final service = AppUpdateService(gateway: gateway);
    await service.init();
    await service.dismissBanner();
    expect(service.showBanner, isFalse);
    expect(service.updateAvailable, isTrue);

    await service.refresh();
    expect(service.showBanner, isFalse);
  });

  test('user tap starts a flexible update then asks to restart', () async {
    final gateway = _FakeGateway()
      ..result = const AppUpdateCheckResult(
        available: true,
        flexibleAllowed: true,
        versionCode: 12,
      );
    final service = AppUpdateService(gateway: gateway);
    await service.init();
    expect(await service.handleUserTap(), 'Restart to finish the update.');
    expect(service.downloaded, isTrue);
    expect(await service.handleUserTap(), isNull);
    expect(gateway.completeCount, 1);
  });

  test('opens Play Store when the update API is unavailable', () async {
    final gateway = _FakeGateway()
      ..result = const AppUpdateCheckResult(
        available: false,
        apiAvailable: false,
      );
    final service = AppUpdateService(gateway: gateway);
    await service.init();
    expect(
      await service.handleUserTap(),
      'Opened the Play Store. Install from there if a newer version is listed.',
    );
    expect(gateway.openStoreCount, 1);
  });
}
