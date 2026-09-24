import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.available,
    this.flexibleAllowed = false,
    this.immediateAllowed = false,
    this.downloaded = false,
    this.inProgress = false,
    this.versionCode,
    this.apiAvailable = true,
  });

  final bool available;
  final bool flexibleAllowed;
  final bool immediateAllowed;
  final bool downloaded;
  final bool inProgress;
  final int? versionCode;
  final bool apiAvailable;
}

enum AppUpdateFlowOutcome { success, denied, failed }

enum AppUpdateInstallEvent { downloading, downloaded, failed }

abstract class AppUpdateGateway {
  Future<AppUpdateCheckResult> check();
  Future<AppUpdateFlowOutcome> startFlexible();
  Future<AppUpdateFlowOutcome> startImmediate();
  Future<void> complete();
  Future<void> openStore();
  Stream<AppUpdateInstallEvent> get events;
}

class NoopAppUpdateGateway implements AppUpdateGateway {
  const NoopAppUpdateGateway();

  @override
  Future<AppUpdateCheckResult> check() async =>
      const AppUpdateCheckResult(available: false, apiAvailable: false);

  @override
  Future<AppUpdateFlowOutcome> startFlexible() async =>
      AppUpdateFlowOutcome.failed;

  @override
  Future<AppUpdateFlowOutcome> startImmediate() async =>
      AppUpdateFlowOutcome.failed;

  @override
  Future<void> complete() async {}

  @override
  Future<void> openStore() async {}

  @override
  Stream<AppUpdateInstallEvent> get events => const Stream.empty();
}

class PlayAppUpdateGateway implements AppUpdateGateway {
  static const packageId = 'com.attendance_flow.myapp';
  static const _market = 'market://details?id=$packageId';
  static const _https =
      'https://play.google.com/store/apps/details?id=$packageId';

  StreamSubscription<InstallStatus>? _sub;
  final _events = StreamController<AppUpdateInstallEvent>.broadcast();

  @override
  Stream<AppUpdateInstallEvent> get events => _events.stream;

  void _ensureListener() {
    _sub ??= InAppUpdate.installUpdateListener.listen((status) {
      switch (status) {
        case InstallStatus.downloading:
        case InstallStatus.pending:
          _events.add(AppUpdateInstallEvent.downloading);
          break;
        case InstallStatus.downloaded:
          _events.add(AppUpdateInstallEvent.downloaded);
          break;
        case InstallStatus.failed:
        case InstallStatus.canceled:
          _events.add(AppUpdateInstallEvent.failed);
          break;
        default:
          break;
      }
    }, onError: (_) {});
  }

  @override
  Future<AppUpdateCheckResult> check() async {
    final info = await InAppUpdate.checkForUpdate();
    _ensureListener();
    final downloaded = info.installStatus == InstallStatus.downloaded;
    final inProgress = info.installStatus == InstallStatus.downloading ||
        info.installStatus == InstallStatus.pending ||
        info.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress;
    return AppUpdateCheckResult(
      available:
          info.updateAvailability == UpdateAvailability.updateAvailable ||
              info.updateAvailability ==
                  UpdateAvailability.developerTriggeredUpdateInProgress ||
              downloaded,
      flexibleAllowed: info.flexibleUpdateAllowed,
      immediateAllowed: info.immediateUpdateAllowed,
      downloaded: downloaded,
      inProgress: inProgress,
      versionCode: info.availableVersionCode,
    );
  }

  AppUpdateFlowOutcome _map(AppUpdateResult result) {
    return switch (result) {
      AppUpdateResult.success => AppUpdateFlowOutcome.success,
      AppUpdateResult.userDeniedUpdate => AppUpdateFlowOutcome.denied,
      AppUpdateResult.inAppUpdateFailed => AppUpdateFlowOutcome.failed,
    };
  }

  @override
  Future<AppUpdateFlowOutcome> startFlexible() async {
    _ensureListener();
    return _map(await InAppUpdate.startFlexibleUpdate());
  }

  @override
  Future<AppUpdateFlowOutcome> startImmediate() async {
    return _map(await InAppUpdate.performImmediateUpdate());
  }

  @override
  Future<void> complete() => InAppUpdate.completeFlexibleUpdate();

  @override
  Future<void> openStore() async {
    final market = Uri.parse(_market);
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    await launchUrl(
      Uri.parse(_https),
      mode: LaunchMode.externalApplication,
    );
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}

class AppUpdateService extends ChangeNotifier {
  static const _dismissedKey = 'update_banner_dismissed_code';
  static const _checkTimeout = Duration(seconds: 12);

  AppUpdateService({
    this.enableStore = true,
    AppUpdateGateway? gateway,
  }) : _gateway = gateway ??
            (enableStore
                ? PlayAppUpdateGateway()
                : const NoopAppUpdateGateway());

  final bool enableStore;
  final AppUpdateGateway _gateway;

  bool updateAvailable = false;
  bool downloaded = false;
  bool downloading = false;
  bool checking = false;
  bool bannerHidden = false;
  bool apiAvailable = false;
  int? availableVersionCode;

  StreamSubscription<AppUpdateInstallEvent>? _eventsSub;
  bool _flexibleAllowed = true;
  bool _immediateAllowed = false;
  int? _dismissedVersionCode;

  bool get showBanner =>
      !bannerHidden && (updateAvailable || downloaded || downloading);

  String get actionLabel {
    if (downloaded) return 'Restart to finish update';
    if (downloading) return 'Downloading update…';
    if (updateAvailable) return 'Update available';
    return 'Check for updates';
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedVersionCode = prefs.getInt(_dismissedKey);
    } catch (_) {}
    _eventsSub ??= _gateway.events.listen(_onInstallEvent);
    await refresh();
  }

  Future<void> refresh() async {
    if (!enableStore || kIsWeb || checking) return;
    checking = true;
    notifyListeners();
    try {
      final info = await _gateway.check().timeout(_checkTimeout);
      _apply(info);
    } on MissingPluginException {
      apiAvailable = false;
    } catch (e) {
      debugPrint('Update check failed: $e');
      apiAvailable = false;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void _apply(AppUpdateCheckResult info) {
    apiAvailable = info.apiAvailable;
    updateAvailable = info.available;
    downloaded = info.downloaded;
    downloading = info.inProgress && !info.downloaded;
    availableVersionCode = info.versionCode;
    _flexibleAllowed = info.flexibleAllowed;
    _immediateAllowed = info.immediateAllowed;
    bannerHidden = !downloaded &&
        !downloading &&
        info.versionCode != null &&
        info.versionCode == _dismissedVersionCode;
  }

  void _onInstallEvent(AppUpdateInstallEvent event) {
    switch (event) {
      case AppUpdateInstallEvent.downloading:
        downloading = true;
        downloaded = false;
      case AppUpdateInstallEvent.downloaded:
        downloading = false;
        downloaded = true;
        updateAvailable = true;
        bannerHidden = false;
      case AppUpdateInstallEvent.failed:
        downloading = false;
    }
    notifyListeners();
  }

  Future<String?> handleUserTap() async {
    if (!enableStore) return "You're on the latest version.";
    if (downloaded) return finishUpdate();
    if (downloading) return 'The update is still downloading.';
    if (!updateAvailable) {
      await refresh();
      if (downloaded) return finishUpdate();
    }
    if (updateAvailable) return startUpdate();
    if (!apiAvailable) {
      await _openStoreSafely();
      return 'Opened the Play Store. Install from there if a newer version is listed.';
    }
    return "You're on the latest version.";
  }

  Future<String?> startUpdate() async {
    if (downloaded) return finishUpdate();
    downloading = true;
    bannerHidden = false;
    notifyListeners();
    try {
      final outcome = _flexibleAllowed
          ? await _gateway.startFlexible()
          : _immediateAllowed
              ? await _gateway.startImmediate()
              : AppUpdateFlowOutcome.failed;
      if (outcome == AppUpdateFlowOutcome.success) {
        if (_flexibleAllowed) {
          downloaded = true;
          downloading = false;
          notifyListeners();
          return 'Restart to finish the update.';
        }
        return null;
      }
      downloading = false;
      notifyListeners();
      if (outcome == AppUpdateFlowOutcome.denied) {
        return 'Update cancelled.';
      }
      await _openStoreSafely();
      return 'Opened the Play Store.';
    } catch (e) {
      debugPrint('Update start failed: $e');
      downloading = false;
      notifyListeners();
      await _openStoreSafely();
      return 'Opened the Play Store.';
    }
  }

  Future<String?> finishUpdate() async {
    try {
      await _gateway.complete().timeout(const Duration(seconds: 20));
      return null;
    } catch (e) {
      debugPrint('Update complete failed: $e');
      await _openStoreSafely();
      return 'Opened the Play Store.';
    }
  }

  Future<void> dismissBanner() async {
    bannerHidden = true;
    _dismissedVersionCode = availableVersionCode;
    notifyListeners();
    if (availableVersionCode == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedKey, availableVersionCode!);
    } catch (_) {}
  }

  Future<void> _openStoreSafely() async {
    try {
      await _gateway.openStore();
    } catch (e) {
      debugPrint('Play Store open failed: $e');
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    final gateway = _gateway;
    if (gateway is PlayAppUpdateGateway) {
      gateway.dispose();
    }
    super.dispose();
  }
}

class AppUpdateScope extends InheritedNotifier<AppUpdateService> {
  const AppUpdateScope({
    super.key,
    required AppUpdateService service,
    required super.child,
  }) : super(notifier: service);

  static AppUpdateService? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppUpdateScope>()
        ?.notifier;
  }
}
