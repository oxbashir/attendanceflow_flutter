import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProService extends ChangeNotifier {
  /// Play Console subscription ID (Monetize → Subscriptions).
  static const subscriptionId = 'attendance_flow_pro';

  /// Play Console base plan ID under that subscription.
  static const basePlanId = 'monthly';

  static const _cacheKey = 'pro_unlocked';
  static const _storeTimeout = Duration(seconds: 20);
  static const unavailableMessage =
      'Purchases are not available right now. You can keep using the free calendar.';
  static const missingProductMessage =
      'Google Play could not find the Pro subscription for this account or country.';

  ProService({this.enableStore = true});

  final bool enableStore;

  bool isPro = false;
  bool storeAvailable = false;
  bool purchasePending = false;
  String? priceLabel;
  String? lastError;

  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isPro = prefs.getBool(_cacheKey) ?? false;
      notifyListeners();
    } catch (_) {}

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

  Future<void> _syncSubscriptionStatus() async {
    if (!storeAvailable) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = InAppPurchase.instance
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response =
            await android.queryPastPurchases().timeout(_storeTimeout);
        if (response.error != null) return;
        final active = response.pastPurchases.any(
          (purchase) =>
              purchase.productID == subscriptionId &&
              (purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored),
        );
        if (active) {
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
          await _unlock();
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
        offerToken: product.offerToken,
      );
    }
    return PurchaseParam(productDetails: product);
  }

  Future<String?> buy() async {
    lastError = null;
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
    try {
      await _syncSubscriptionStatus();
      if (!isPro) {
        lastError = 'No Pro purchase found on this Google account.';
        notifyListeners();
      }
      return lastError;
    } catch (_) {
      lastError = unavailableMessage;
      notifyListeners();
      return lastError;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
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
