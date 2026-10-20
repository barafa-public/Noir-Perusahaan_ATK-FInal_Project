import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'product_service.dart';

/// Keranjang Customer. Sumber data: tabel cart_items (SQLite, per akun)
/// digabung dengan cache produk, sehingga harga/stok ikut segar setelah sinkronisasi.
class CartService extends ChangeNotifier {
  CartService._() {
    ProductService.instance.changes.addListener(_onProductsChanged);
  }
  static final CartService instance = CartService._();

  String? _userId;
  List<CartItemModel> _lines = const [];
  int _seq = 0;

  List<CartItemModel> get lines => _lines;
  bool get isEmpty => _lines.isEmpty;
  int get totalQty => _lines.fold(0, (sum, l) => sum + l.qty);
  int get total => _lines.fold(0, (sum, l) => sum + l.subtotal);

  int qtyOf(String productId) {
    for (final l in _lines) {
      if (l.product.id == productId) return l.qty;
    }
    return 0;
  }

  void _onProductsChanged() {
    if (_userId != null) load();
  }

  /// Memuat ulang keranjang akun yang sedang login.
  Future<void> load() async {
    final uid = AuthService.instance.user?.id;
    if (uid != _userId) {
      // Ganti akun di perangkat yang sama: jangan tampilkan keranjang akun lama.
      _userId = uid;
      _lines = const [];
      notifyListeners();
    }
    if (uid == null) return;

    final seq = ++_seq;
    final db = DbHelper.instance;
    final cart = await db.getCart(uid);

    final lines = <CartItemModel>[];
    for (final e in cart.entries) {
      final p = await db.getProduct(e.key);
      if (p == null) {
        // Produk sudah tidak ada di katalog: buang dari keranjang.
        await db.setCartQty(uid, e.key, 0);
        continue;
      }
      lines.add(CartItemModel(product: p, qty: e.value));
    }
    lines.sort(
      (a, b) =>
          a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()),
    );

    if (seq != _seq) return; // ada load yang lebih baru
    _lines = lines;
    notifyListeners();
  }

  /// Menambah [qty], dibatasi stok cache. false = tidak ada yang ditambahkan.
  Future<bool> add(ProductModel p, {int qty = 1}) async {
    final uid = AuthService.instance.user?.id;
    if (uid == null || p.stock <= 0 || qty <= 0) return false;

    // Baca dari database (bukan dari _lines) agar tidak menimpa dengan data usang.
    final current = (await DbHelper.instance.getCart(uid))[p.id] ?? 0;
    final next = math.min(current + qty, p.stock);
    if (next <= current) return false;

    await DbHelper.instance.setCartQty(uid, p.id, next);
    await load();
    return true;
  }

  /// qty <= 0 menghapus baris.
  Future<void> setQty(String productId, int qty) async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) return;
    await DbHelper.instance.setCartQty(uid, productId, qty);
    await load();
  }

  Future<void> remove(String productId) => setQty(productId, 0);

  Future<void> clear() async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) return;
    await DbHelper.instance.clearCart(uid);
    await load();
  }
}
