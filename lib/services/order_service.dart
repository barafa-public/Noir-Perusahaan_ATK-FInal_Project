import 'package:flutter/foundation.dart';

import '../models/cart_item_model.dart';
import '../models/order_model.dart';
import 'api_client.dart';

class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();

  /// Naik setiap kali pesanan baru dibuat; daftar pesanan memuat ulang.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Membuat pesanan dari keranjang. Hanya id produk dan jumlah yang dikirim;
  /// harga dihitung server. Melempar [ApiException] bila gagal
  /// (mis. INSUFFICIENT_STOCK, PRODUCT_NOT_FOUND, offline).
  Future<OrderModel> create(List<CartItemModel> lines, {String? note}) async {
    final res = await ApiClient.instance.post(
      '/orders',
      body: {
        'items': [
          for (final l in lines) {'product_id': l.product.id, 'qty': l.qty},
        ],
        'note': (note ?? '').trim(),
      },
    );
    final order = OrderModel.fromJson(res['order'] as Map<String, dynamic>);
    changes.value++;
    return order;
  }

  /// Pesanan milik akun yang login (maksimal 50 terbaru), tanpa item.
  Future<List<OrderModel>> fetchMine() async {
    final res = await ApiClient.instance.get('/orders');
    return ((res['orders'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(OrderModel.fromJson)
        .toList();
  }

  Future<OrderModel> fetchOne(String id) async {
    final res = await ApiClient.instance.get('/orders/$id');
    return OrderModel.fromJson(res['order'] as Map<String, dynamic>);
  }
}
