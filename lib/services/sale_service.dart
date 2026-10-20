import 'dart:async';
import 'dart:math' as math;

import '../models/sale_model.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'product_service.dart';
import 'sync_service.dart';

class SaleException implements Exception {
  final String message;
  const SaleException(this.message);

  @override
  String toString() => message;
}

/// Penjualan langsung oleh User internal. Alurnya offline-first:
/// divalidasi terhadap stok efektif lokal, ditulis ke SQLite, lalu dikirim
/// ke server di latar belakang. Pengurangan stok yang sah terjadi di server
/// (record_sale); sebelum itu, stok efektif lokal sudah memperhitungkannya.
class SaleService {
  SaleService._();
  static final SaleService instance = SaleService._();

  /// Mencatat penjualan satu produk. Melempar [SaleException] bila ditolak
  /// (bukan internal, jumlah tidak valid, produk tidak ada, stok kurang).
  Future<SaleModel> record({
    required String productId,
    required int qty,
  }) async {
    final user = AuthService.instance.user;
    if (user == null || !user.isInternal) {
      throw const SaleException(
        'Hanya User internal yang dapat mencatat penjualan.',
      );
    }
    if (qty <= 0) throw const SaleException('Jumlah harus lebih dari 0.');

    // Stok efektif (sudah dikurangi penjualan lokal yang belum terkirim).
    final p = await DbHelper.instance.getProduct(productId);
    if (p == null) {
      throw const SaleException(
        'Produk tidak ditemukan. Sinkronkan data lalu coba lagi.',
      );
    }
    if (qty > p.stock) {
      throw SaleException(
        p.stock <= 0
            ? 'Stok ${p.name} habis.'
            : 'Stok ${p.name} tidak cukup. Tersedia ${p.stock}.',
      );
    }

    final sale = SaleModel(
      id: _uuidV4(),
      productId: p.id,
      productName: p.name,
      unitPrice: p.price,
      qty: qty,
      total: p.price * qty,
      cashierId: user.id,
      soldAt: SaleModel.normalizeIso(DateTime.now()),
    );
    await DbHelper.instance.insertSale(sale);

    SyncService.instance.notifySalesChanged();
    ProductService.instance.notifyChanged(); // stok efektif berubah
    unawaited(SyncService.instance.syncAll());
    return sale;
  }

  /// Penjualan yang ditolak server: coba kirim lagi.
  Future<void> retry(String saleId) async {
    await DbHelper.instance.retrySale(saleId);
    SyncService.instance.notifySalesChanged();
    ProductService.instance.notifyChanged();
    unawaited(SyncService.instance.syncAll());
  }

  /// Penjualan yang ditolak server: buang dari perangkat.
  Future<void> discardRejected(String saleId) async {
    await DbHelper.instance.deleteRejectedSale(saleId);
    SyncService.instance.notifySalesChanged();
  }

  static String _uuidV4() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versi 4
    b[8] = (b[8] & 0x3f) | 0x80; // varian RFC 4122
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
