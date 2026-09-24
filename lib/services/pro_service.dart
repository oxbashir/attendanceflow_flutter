import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'entitlement_backend.dart';

class ProService extends ChangeNotifier {
  /// Play Console subscription ID (Monetize → Subscriptions).
  static const subscriptionId = 'attendance_flow_pro';

  /// Play Console base plan ID under that subscription.
  static const basePlanId = 'monthly';

  static const _cacheKey = 'pro_unlocked';
  static const _pendingTokenKey = 'pro_pending_token';
  static const _storeTimeout = Duration(seconds: 20);
  static const unavailableMessage =
      'Purchases are not available right now. You can keep using the free calendar.';
  static const missingProductMessage =
      'Google Play could not find the Pro subscription for this account or country.';
  static const signInRequiredMessage =
      'Sign in with Google first so Pro follows you to any device.';

  ProService({
    this.enableStore = true,
    this.auth,
    EntitlementBackend? backend,
  }) : _backend = backend;

  final bool enableStore;

  /// Optional. When present and enabled, Pro is tied to the signed-in account
  /// and verified on the server instead of only on this device.
  final AuthService? auth;
  final EntitlementBackend? _backend;

  bool isPro = false;
  bool storeAvailable = false;
  bool purchasePending = false;
  String? priceLabel;
  String? lastError;

  /// True when the current [isPro] value came from the server.
  bool serverVerified = false;
  EntitlementStatus? entitlement;

  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  StreamSubscription<EntitlementStatus>? _watchSub;
  String? _watchedUid;
  String? _lastLocalToken;

  /// Accounts are wired up and nobody is signed in yet.
  bool get requiresSignIn =>
      auth != null && auth!.enabled && !auth!.isSignedIn && _backend != null;

  bool get accountsEnabled => auth != null && auth!.enabled && _backend != null;

  /// Debug-only switch to test the free tier on a device that owns Pro:
  /// `flutter run --dart-define=FORCE_FREE=true`. Ignored in release builds.
  static const bool forceFree =
      kDebugMode && bool.fromEnvironment('FORCE_FREE', defaultValue: false);

  Future<void> init() async {
    if (forceFree) {
      isPro = false;
      storeAvailable = true;
      priceLabel = 'FREE MODE';
      debugPrint('ProService: FORCE_FREE is on, Pro is disabled for testing.');
      notifyListeners();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      isPro = prefs.getBool(_cacheKey) ?? false;
    } catch (_) {}
    if (requiresSignIn) {
      isPro = false;
    }
    notifyListeners();

    auth?.addListener(_onAuthChanged);

    if (!enableStore || kIsWeb) return;
    try {
      final iap = InAppPurchase.instance;
      storeAvailable = await iap.isAvailable().timeout(_storeTimeout);
      if (!storeAvailable) {
        notifyListeners();
        return;
      }
      _sub = iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          lastError = unavailableMessage;
          purchasePending = false;
          notifyListeners();
        },
      );
      await _queryProduct();
      await _syncSubscriptionStatus();
    } catch (e) {
      debugPrint('IAP init failed: $e');
      storeAvailable = false;
      notifyListeners();
    }
  }

  void _onAuthChanged() {
    final uid = auth?.uid;
    if (uid == _watchedUid) return;
    _watchSub?.cancel();
    _watchSub = null;
    _watchedUid = uid;
    if (uid == null || _backend == null) {
      // Signed out: Pro lives on the account, not on this device.
      serverVerified = false;
      entitlement = null;
      unawaited(_lock());
      return;
    }
    _watchSub = _backend.watch(uid).listen(_applyServerStatus, onError: (_) {});
    unawaited(_serverSync(purchaseToken: _lastLocalToken));
  }

  Future<void> _queryProduct() async {
    ProductDetailsResponse? response;
    for (var attempt = 0; attempt < 3; attempt++) {
      response = await InAppPurchase.instance
          .queryProductDetails({subscriptionId}).timeout(_storeTimeout);
      debugPrint(
        'IAP query attempt=$attempt id=$subscriptionId '
        'found=${response.productDetails.map((p) => p.id).toList()} '
        'notFound=${response.notFoundIDs} '
        'error=${response.error}',
      );
      if (response.productDetails.isNotEmpty) break;
      await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
    }
    final products = response?.productDetails ?? const <ProductDetails>[];
    if (products.isEmpty) {
      lastError = missingProductMessage;
      notifyListeners();
      return;
    }
    _product = _pickMonthly(products) ?? products.first;
    priceLabel = _product!.price;
    lastError = null;
    notifyListeners();
  }

  ProductDetails? _pickMonthly(List<ProductDetails> products) {
    for (final product in products) {
      if (product is! GooglePlayProductDetails) continue;
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) continue;
      if (offers[index].basePlanId == basePlanId) return product;
    }
    return null;
  }

  String? _tokenOf(PurchaseDetails purchase) {
    final token = purchase.verificationData.serverVerificationData;
    return token.isEmpty ? null : token;
  }

  Future<void> _syncSubscriptionStatus() async {
    if (!storeAvailable) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = InAppPurchase.instance
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response =
            await android.queryPastPurchases().timeout(_storeTimeout);
        if (response.error != null) return;
        PurchaseDetails? activePurchase;
        for (final purchase in response.pastPurchases) {
          if (purchase.productID == subscriptionId &&
              (purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored)) {
            activePurchase = purchase;
            break;
          }
        }
        _lastLocalToken =
            activePurchase == null ? null : _tokenOf(activePurchase);

        if (requiresSignIn) {
          await _lock();
          return;
        }
        if (_canUseServer) {
          final ok = await _serverSync(purchaseToken: _lastLocalToken);
          if (ok) return;
          // Server unreachable: fall through to the device's own answer, but
          // never demote a server-verified Pro just because we are offline.
          if (serverVerified) return;
        }
        if (activePurchase != null) {
          await _unlock();
        } else {
          await _lock();
        }
        return;
      }
      await InAppPurchase.instance.restorePurchases().timeout(_storeTimeout);
    } catch (_) {
      // Keep the cached entitlement if Play Billing is unreachable.
    }
  }

  bool get _canUseServer =>
      _backend != null && auth != null && auth!.enabled && auth!.isSignedIn;

  /// Asks the server to verify; returns false when it could not be reached.
  Future<bool> _serverSync({String? purchaseToken}) async {
    if (!_canUseServer) return false;
    try {
      String? token = purchaseToken;
      if (token == null) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString(_pendingTokenKey);
      }
      final status = await _backend!.sync(purchaseToken: token);
      _applyServerStatus(status);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingTokenKey);
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('Entitlement sync failed: $e');
      if (purchaseToken != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_pendingTokenKey, purchaseToken);
        } catch (_) {}
      }
      return false;
    }
  }

  void _applyServerStatus(EntitlementStatus status) {
    entitlement = status;
    serverVerified = true;
    if (status.active) {
      unawaited(_unlock());
    } else {
      unawaited(_lock());
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != subscriptionId) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          purchasePending = true;
          lastError = null;
          notifyListeners();
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final token = _tokenOf(purchase);
          _lastLocalToken = token ?? _lastLocalToken;
          var handled = false;
          if (_canUseServer && token != null) {
            handled = await _serverSync(purchaseToken: token);
          }
          if (!handled) {
            if (requiresSignIn) {
              purchasePending = false;
              notifyListeners();
              continue;
            }
            // Either accounts are off, or the server is unreachable right
            // now; the token is queued and retried on the next launch.
            await _unlock();
          }
          purchasePending = false;
          lastError = null;
          notifyListeners();
        case PurchaseStatus.error:
          purchasePending = false;
          lastError = unavailableMessage;
          notifyListeners();
        case PurchaseStatus.canceled:
          purchasePending = false;
          lastError = null;
          notifyListeners();
      }
      if (purchase.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (_) {}
      }
    }
  }

  Future<void> _unlock() async {
    if (requiresSignIn) {
      await _lock();
      return;
    }
    isPro = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey, true);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _lock() async {
    isPro = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey, false);
    } catch (_) {}
    notifyListeners();
  }

  PurchaseParam _purchaseParam(ProductDetails product) {
    if (product is GooglePlayProductDetails) {
      return GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: _offerTokenFor(product),
      );
    }
    return PurchaseParam(productDetails: product);
  }

  String? _offerTokenFor(GooglePlayProductDetails product) {
    final current = product.offerToken;
    if (current != null && current.isNotEmpty) return current;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (offers == null || offers.isEmpty) return null;
    for (final offer in offers) {
      if (offer.basePlanId == basePlanId) return offer.offerIdToken;
    }
    return offers.first.offerIdToken;
  }

  Future<String?> buy() async {
    lastError = null;
    if (isPro) return null;
    if (requiresSignIn) {
      lastError = signInRequiredMessage;
      notifyListeners();
      return lastError;
    }
    if (forceFree) {
      // Test mode: pretend the purchase went through without touching Play.
      await _unlock();
      return null;
    }
    // Already subscribed on this Play account: restore instead of opening
    // a second purchase (Play then shows "Billing is not configured").
    await _syncSubscriptionStatus();
    if (isPro) return null;
    try {
      if (_product == null) {
        await _queryProduct();
      }
    } catch (_) {
      lastError = unavailableMessage;
      notifyListeners();
      return lastError;
    }
    if (_product == null) {
      lastError = missingProductMessage;
      notifyListeners();
      return lastError;
    }
    purchasePending = true;
    notifyListeners();
    try {
      final started = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: _purchaseParam(_product!),
      );
      if (!started) {
        purchasePending = false;
        lastError = unavailableMessage;
        notifyListeners();
        return lastError;
      }
    } catch (e) {
      debugPrint('IAP buy failed: $e');
      purchasePending = false;
      lastError = unavailableMessage;
      notifyListeners();
      return lastError;
    }
    return null;
  }

  Future<String?> restore() async {
    lastError = null;
    notifyListeners();
    if (forceFree) {
      lastError = 'FORCE_FREE test mode: nothing to restore.';
      notifyListeners();
      return lastError;
    }
    if (requiresSignIn) {
      lastError = signInRequiredMessage;
      notifyListeners();
      return lastError;
    }
    try {
      await _syncSubscriptionStatus();
      if (!isPro) {
        lastError = _canUseServer
            ? 'No active Pro subscription is linked to this account.'
            : 'No Pro purchase found on this Google account.';
        notifyListeners();
      }
      return lastError;
    } catch (_) {
      lastError = unavailableMessage;
      notifyListeners();
      return lastError;
    }
  }

  /// Re-checks Play + server entitlement (e.g. after sign-in from the paywall).
  Future<void> refreshEntitlement() async {
    if (requiresSignIn) return;
    await _syncSubscriptionStatus();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _watchSub?.cancel();
    auth?.removeListener(_onAuthChanged);
    super.dispose();
  }
}

class ProScope extends InheritedNotifier<ProService> {
  const ProScope({
    super.key,
    required ProService service,
    required super.child,
  }) : super(notifier: service);

  static ProService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ProScope>()?.notifier;
  }
}
