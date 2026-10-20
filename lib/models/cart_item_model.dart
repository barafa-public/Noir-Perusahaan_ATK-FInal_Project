import 'product_model.dart';

/// Satu baris keranjang: produk (dari cache SQLite) + jumlah.
class CartItemModel {
  final ProductModel product;
  final int qty;

  const CartItemModel({required this.product, required this.qty});

  /// Perkiraan berdasarkan harga cache. Harga resmi dihitung server.
  int get subtotal => product.price * qty;

  /// Berdasarkan stok cache; stok sebenarnya diperiksa server.
  bool get exceedsStock => qty > product.stock;
}
