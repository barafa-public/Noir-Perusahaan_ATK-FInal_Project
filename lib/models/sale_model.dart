class SaleModel {
  final String id; // UUID dibuat di perangkat
  final String productId;
  final String productName;
  final int unitPrice;
  final int qty;
  final int total;
  final String cashierId;

  /// ISO-8601 UTC.
  final String soldAt;

  /// true = sudah diterima server.
  final bool synced;

  /// Alasan penolakan server (mis. stok kurang). Terisi berarti tidak dikirim ulang.
  final String? syncError;

  const SaleModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    required this.total,
    required this.cashierId,
    required this.soldAt,
    this.synced = false,
    this.syncError,
  });

  bool get isPending => !synced && syncError == null;
  bool get isRejected => !synced && syncError != null;

  factory SaleModel.fromDb(Map<String, Object?> m) => SaleModel(
    id: m['id'] as String,
    productId: m['product_id'] as String,
    productName: m['product_name'] as String,
    unitPrice: m['unit_price'] as int,
    qty: m['qty'] as int,
    total: m['total'] as int,
    cashierId: m['cashier_id'] as String,
    soldAt: m['sold_at'] as String,
    synced: (m['synced'] as int) == 1,
    syncError: m['sync_error'] as String?,
  );

  Map<String, Object?> toDb() => {
    'id': id,
    'product_id': productId,
    'product_name': productName,
    'unit_price': unitPrice,
    'qty': qty,
    'total': total,
    'cashier_id': cashierId,
    'sold_at': soldAt,
    'synced': synced ? 1 : 0,
    'sync_error': syncError,
  };

  /// Waktu -> teks ISO-8601 UTC berpresisi milidetik (selalu ".SSSZ"), agar
  /// perbandingan dan pengurutan sebagai teks di SQLite konsisten.
  static String normalizeIso(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
    d.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  /// Dari baris tabel sales di server (selalu dianggap sudah terkirim).
  factory SaleModel.fromServer(Map<String, dynamic> j) => SaleModel(
    id: j['id'] as String,
    productId: j['product_id'] as String,
    productName: j['product_name'] as String,
    unitPrice: (j['unit_price'] as num).toInt(),
    qty: (j['qty'] as num).toInt(),
    total: (j['total'] as num).toInt(),
    cashierId: j['cashier_id'] as String,
    soldAt: normalizeIso(DateTime.parse(j['sold_at'] as String)),
    synced: true,
  );

  /// Hanya field yang boleh ditentukan klien. Harga dan kasir ditentukan server.
  Map<String, dynamic> toPushJson() => {
    'id': id,
    'product_id': productId,
    'qty': qty,
    'sold_at': soldAt,
  };
}
