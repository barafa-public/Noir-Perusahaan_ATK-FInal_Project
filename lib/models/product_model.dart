class ProductModel {
  final String id;
  final String sku;
  final String name;
  final String category;
  final String? description;
  final int price; // rupiah
  final int stock;
  final int minStock;
  final bool isActive;

  /// ISO-8601 UTC persis seperti dari server (dipakai sebagai kursor sinkronisasi).
  final String updatedAt;

  const ProductModel({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    this.description,
    required this.price,
    required this.stock,
    required this.minStock,
    required this.isActive,
    required this.updatedAt,
  });

  bool get isLowStock => stock <= minStock;
  bool get isOutOfStock => stock <= 0;

  /// Dari respons Edge Function.
  factory ProductModel.fromJson(Map<String, dynamic> j) => ProductModel(
    id: j['id'] as String,
    sku: j['sku'] as String,
    name: j['name'] as String,
    category: j['category'] as String,
    description: j['description'] as String?,
    price: (j['price'] as num).toInt(),
    stock: (j['stock'] as num).toInt(),
    minStock: (j['min_stock'] as num).toInt(),
    isActive: (j['is_active'] as bool?) ?? true,
    updatedAt: j['updated_at'] as String,
  );

  /// Dari baris SQLite.
  factory ProductModel.fromDb(Map<String, Object?> m) => ProductModel(
    id: m['id'] as String,
    sku: m['sku'] as String,
    name: m['name'] as String,
    category: m['category'] as String,
    description: m['description'] as String?,
    price: m['price'] as int,
    stock: m['stock'] as int,
    minStock: m['min_stock'] as int,
    isActive: (m['is_active'] as int) == 1,
    updatedAt: m['updated_at'] as String,
  );

  Map<String, Object?> toDb() => {
    'id': id,
    'sku': sku,
    'name': name,
    'category': category,
    'description': description,
    'price': price,
    'stock': stock,
    'min_stock': minStock,
    'is_active': isActive ? 1 : 0,
    'updated_at': updatedAt,
  };
}
