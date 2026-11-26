import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'dart:io' show Platform;

/// Acquisto una tantum di FamilyRecipes Pro (Google Play e App Store).
class ProService {
  static const String productId = 'familyrecipes_pro';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool storeAvailable = false;
  ProductDetails? product;
  bool busy = false;
  String? lastError;

  Future<void> init({
    required void Function() onOwned,
    required void Function() onChanged,
    void Function()? onRevoked,
  }) async {
    if (kIsWeb) return;
    try {
      _sub ??= _iap.purchaseStream.listen((list) async {
        for (final p in list) {
          if (p.productID != productId) continue;
          switch (p.status) {
            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              onOwned();
              busy = false;
              break;
            case PurchaseStatus.error:
              lastError = p.error?.message;
              busy = false;
              break;
            case PurchaseStatus.pending:
              busy = true;
              break;
            default:
              busy = false;
          }
          if (p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {}
          }
        }
        onChanged();
      }, onError: (_) {
        busy = false;
        onChanged();
      });
      storeAvailable = await _iap.isAvailable();
      if (storeAvailable) {
        final r = await _iap.queryProductDetails({productId});
        if (r.productDetails.isNotEmpty) product = r.productDetails.first;
        if (!Platform.isIOS) await _iap.restorePurchases();
        // Rimborso o acquisto annullato: Google Play non elenca più il prodotto tra quelli posseduti.
        if (onRevoked != null && await ownedOnPlay() == false) onRevoked();
      }
    } catch (_) {
      storeAvailable = false;
    }
    onChanged();
  }

  /// Solo Android: true/false se Google Play risponde con l'elenco degli acquisti, null se non si sa
  /// (offline, errore, altra piattaforma): in quel caso non si toglie niente.
  Future<bool?> ownedOnPlay() async {
    if (kIsWeb || !Platform.isAndroid || !storeAvailable) return null;
    try {
      final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final r = await addition.queryPastPurchases().timeout(const Duration(seconds: 20));
      if (r.error != null) return null;
      return r.pastPurchases.any((p) => p.productID == productId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> buy() async {
    if (kIsWeb) return false;
    final p = product;
    if (!storeAvailable || p == null) return false;
    lastError = null;
    busy = true;
    try {
      return await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
    } catch (e) {
      busy = false;
      lastError = '$e';
      return false;
    }
  }

  Future<void> restore() async {
    if (kIsWeb) return;
    if (!storeAvailable) return;
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
  }
}
