import 'package:flutter/foundation.dart';

import '../models/product_model.dart';
import 'api_client.dart';
import 'db_helper.dart';

class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  /// Naik setiap kali cache produk berubah (sinkronisasi atau simpan produk).
  /// Layar yang menampilkan produk mendengarkan ini untuk memuat ulang.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  void notifyChanged() => changes.value++;

  /// Menambah produk ([id] null) atau mengubah produk yang ada.
  /// Wajib online; hasil resmi dari server langsung ditulis ke cache SQLite.
  /// Melempar [ApiException] bila gagal (mis. SKU_TAKEN, offline).
  Future<ProductModel> save({
    String? id,
    required String sku,
    required String name,
    required String category,
    String? description,
    required int price,
    required int stock,
    required int minStock,
  }) async {
    final body = <String, dynamic>{
      if (id == null) 'sku': sku, // SKU tidak diubah saat edit
      'name': name,
      'category': category,
      'description': description ?? '', // string kosong = hapus deskripsi
      'price': price,
      'stock': stock,
      'min_stock': minStock,
    };

    final res = await ApiClient.instance
        .post(id == null ? '/products' : '/products/$id', body: body);

    final product =
        ProductModel.fromJson(res['product'] as Map<String, dynamic>);
    await DbHelper.instance.applyProductChanges([product]);
    notifyChanged();
    return product;
  }

  /// Menambah stok [qty] unit secara atomik di server (bukan menimpa).
  /// Wajib online; hasil resmi dari server ditulis ke cache SQLite.
  /// Melempar [ApiException] bila gagal.
  Future<ProductModel> addStock(String productId, int qty) async {
    final res = await ApiClient.instance.post(
      '/products/$productId/stock',
      body: {'qty': qty},
    );
    final product =
        ProductModel.fromJson(res['product'] as Map<String, dynamic>);
    await DbHelper.instance.applyProductChanges([product]);
    notifyChanged();
    return product;
  }
}
