class OrderStatus {
  OrderStatus._();
  static const String ordered = 'Dipesan';
  static const String processing = 'Diproses';
  static const String done = 'Selesai';
  static const String cancelled = 'Dibatalkan';
}

class OrderItemModel {
  final String productId;
  final String productName;
  final int unitPrice;
  final int qty;
  final int subtotal;

  const OrderItemModel({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    required this.subtotal,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> j) => OrderItemModel(
    productId: j['product_id'] as String,
    productName: j['product_name'] as String,
    unitPrice: (j['unit_price'] as num).toInt(),
    qty: (j['qty'] as num).toInt(),
    subtotal: (j['subtotal'] as num).toInt(),
  );
}

class OrderModel {
  final String id;
  final String orderNo;
  final String status;
  final int total;
  final String? note;
  final String? cancelReason;
  final String createdAt; // ISO-8601 UTC
  final String updatedAt;
  final List<OrderItemModel> items; // kosong pada daftar (tanpa detail)

  const OrderModel({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.total,
    this.note,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
    id: j['id'] as String,
    orderNo: j['order_no'] as String,
    status: j['status'] as String,
    total: (j['total'] as num).toInt(),
    note: j['note'] as String?,
    cancelReason: j['cancel_reason'] as String?,
    createdAt: j['created_at'] as String,
    updatedAt: j['updated_at'] as String,
    items: ((j['order_items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(OrderItemModel.fromJson)
        .toList(),
  );
}
