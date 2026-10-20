import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cart_item_model.dart';
import '../models/order_model.dart';
import 'api_client.dart';
import 'sync_service.dart';

class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();

  /// Naik setiap kali pesanan dibuat atau statusnya diubah dari aplikasi ini;
  /// daftar pesanan memuat ulang.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // ------------------------------------------------------------------
  // Customer
  // ------------------------------------------------------------------

  /// Membuat pesanan dari keranjang. Hanya id produk dan jumlah yang dikirim;
  /// harga dihitung server. Melempar [ApiException] bila gagal
  /// (mis. INSUFFICIENT_STOCK, PRODUCT_NOT_FOUND, offline).
  Future<OrderModel> create(List<CartItemModel> lines, {String? note}) async {
    final res = await ApiClient.instance.post('/orders', body: {
      'items': [
        for (final l in lines) {'product_id': l.product.id, 'qty': l.qty},
      ],
      'note': (note ?? '').trim(),
    });
    final order = OrderModel.fromJson(res['order'] as Map<String, dynamic>);
    changes.value++;
    return order;
  }

  /// Pesanan milik akun yang login (maksimal 50 terbaru), tanpa item.
  Future<List<OrderModel>> fetchMine() async {
    final res = await ApiClient.instance.get('/orders');
    return _parseList(res);
  }

  // ------------------------------------------------------------------
  // Customer dan User internal
  // ------------------------------------------------------------------

  Future<OrderModel> fetchOne(String id) async {
    final res = await ApiClient.instance.get('/orders/$id');
    return OrderModel.fromJson(res['order'] as Map<String, dynamic>);
  }

  // ------------------------------------------------------------------
  // User internal
  // ------------------------------------------------------------------

  /// Semua pesanan dengan [status] tertentu, terbaru dulu, per halaman.
  Future<List<OrderModel>> fetchByStatus(
    String status, {
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await ApiClient.instance.get(
      '/orders?status=${Uri.encodeQueryComponent(status)}'
      '&limit=$limit&offset=$offset',
    );
    return _parseList(res);
  }

  /// Dipesan -> Diproses. Server memvalidasi stok semua item lalu
  /// mengurangi stok dalam satu transaksi.
  Future<OrderModel> process(String id) => _act(id, 'process');

  /// Diproses -> Selesai.
  Future<OrderModel> complete(String id) => _act(id, 'complete');

  /// Dipesan/Diproses -> Dibatalkan. Stok kembali hanya jika sudah Diproses.
  Future<OrderModel> cancel(String id, String reason) =>
      _act(id, 'cancel', body: {'reason': reason.trim()});

  Future<OrderModel> _act(
    String id,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final res = await ApiClient.instance.post('/orders/$id/$action', body: body);
    final order = OrderModel.fromJson(res['order'] as Map<String, dynamic>);
    changes.value++;
    // Stok di server berubah (kecuali pada 'complete'); perbarui cache produk.
    if (action != 'complete') {
      unawaited(
        SyncService.instance.syncProducts().then((_) {}, onError: (_) {}),
      );
    }
    return order;
  }

  List<OrderModel> _parseList(Map<String, dynamic> res) {
    return ((res['orders'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(OrderModel.fromJson)
        .toList();
  }
}