import 'package:flutter/foundation.dart';

import '../models/product_model.dart';
import '../models/sale_model.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'product_service.dart';

class SyncReport {
  final int productsReceived;
  final int salesReceived;
  final int salesSent;
  final int salesRejected;
  final String? error;

  const SyncReport({
    this.productsReceived = 0,
    this.salesReceived = 0,
    this.salesSent = 0,
    this.salesRejected = 0,
    this.error,
  });

  @override
  String toString() =>
      'SyncReport(produk: $productsReceived, penjualan diterima: $salesReceived, '
      'terkirim: $salesSent, ditolak: $salesRejected, error: $error)';
}

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _kProductsSince = 'products_last_sync';
  static const _kSalesSince = 'sales_last_pull';
  static const _pageSize = 200;

  /// Status HTTP yang berarti "penjualan INI ditolak" (bukan gangguan sementara).
  static const _rejectCodes = {404, 409, 422};

  /// Naik setiap kali tabel sales lokal berubah (dicatat, terkirim, ditolak,
  /// atau diterima dari server). Layar riwayat penjualan memuat ulang.
  final ValueNotifier<int> salesChanged = ValueNotifier<int>(0);

  void notifySalesChanged() => salesChanged.value++;

  Future<SyncReport>? _running;
  bool _rerun = false;

  /// Kirim penjualan tertunda, tarik penjualan baru dari server (internal),
  /// lalu tarik perubahan produk. Tidak melempar error; lihat [SyncReport.error].
  ///
  /// Bila dipanggil saat sinkronisasi sedang berjalan, satu putaran lagi
  /// dijalankan setelahnya, sehingga data yang baru ditulis (mis. penjualan
  /// yang baru dicatat) tidak tertinggal sampai sinkronisasi berikutnya.
  Future<SyncReport> syncAll() {
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    return _running = _runLoop().whenComplete(() => _running = null);
  }

  Future<SyncReport> _runLoop() async {
    SyncReport report;
    do {
      _rerun = false;
      report = await _run();
    } while (_rerun);
    return report;
  }

  Future<SyncReport> _run() async {
    final user = AuthService.instance.user;
    if (user == null) return const SyncReport(error: 'Belum login.');

    var sent = 0, rejected = 0, salesIn = 0, productsIn = 0;
    String? error;

    // Urutan penting: kirim dulu, tarik penjualan, baru tarik produk, agar
    // stok yang terambil sudah memperhitungkan penjualan yang baru dikirim.
    if (user.isInternal) {
      final push = await pushSales(user.id);
      sent = push.sent;
      rejected = push.rejected;
      error = push.error;

      try {
        salesIn = await pullSales();
      } on ApiException catch (e) {
        error ??= e.message;
      }
    }

    try {
      productsIn = await syncProducts();
    } on ApiException catch (e) {
      error ??= e.message;
    }

    return SyncReport(
      productsReceived: productsIn,
      salesReceived: salesIn,
      salesSent: sent,
      salesRejected: rejected,
      error: error,
    );
  }

  // -------------------------------------------------------------------
  // Supabase -> SQLite: katalog produk
  // -------------------------------------------------------------------

  /// Menarik produk yang berubah sejak sinkronisasi terakhir.
  /// [full] = abaikan kursor dan tarik semua produk aktif.
  /// Mengembalikan jumlah baris yang diterima. Melempar [ApiException] bila gagal.
  Future<int> syncProducts({bool full = false}) async {
    final db = DbHelper.instance;
    final since = full ? null : await db.getMeta(_kProductsSince);

    var offset = 0;
    var received = 0;
    String? newest = since;
    DateTime? newestAt = since == null ? null : DateTime.tryParse(since);

    while (true) {
      final path = StringBuffer('/products?limit=$_pageSize&offset=$offset');
      if (since != null) {
        path.write('&since=${Uri.encodeQueryComponent(since)}');
      }

      final res = await ApiClient.instance.get(path.toString());
      final rows = ((res['products'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ProductModel.fromJson)
          .toList();

      await db.applyProductChanges(rows);
      received += rows.length;

      for (final p in rows) {
        final at = DateTime.tryParse(p.updatedAt);
        if (at != null && (newestAt == null || at.isAfter(newestAt))) {
          newestAt = at;
          newest = p.updatedAt;
        }
      }

      if (rows.length < _pageSize) break;
      offset += rows.length;
    }

    // Kursor disimpan hanya setelah semua halaman berhasil diterapkan.
    if (newest != null) await db.setMeta(_kProductsSince, newest);
    ProductService.instance.notifyChanged();
    return received;
  }

  // -------------------------------------------------------------------
  // Supabase -> SQLite: riwayat penjualan semua perangkat (internal)
  // -------------------------------------------------------------------

  /// Menarik penjualan yang diterima server sejak penarikan terakhir
  /// (termasuk milik perangkat/kasir lain) dan menyimpannya sebagai synced.
  /// Melempar [ApiException] bila gagal.
  Future<int> pullSales({bool full = false}) async {
    final db = DbHelper.instance;
    final since = full ? null : await db.getMeta(_kSalesSince);

    var offset = 0;
    var received = 0;
    String? newest = since;
    DateTime? newestAt = since == null ? null : DateTime.tryParse(since);

    while (true) {
      final path = StringBuffer('/sales?limit=$_pageSize&offset=$offset');
      if (since != null) {
        path.write('&since=${Uri.encodeQueryComponent(since)}');
      }

      final res = await ApiClient.instance.get(path.toString());
      final raw = ((res['sales'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

      await db.upsertServerSales(raw.map(SaleModel.fromServer).toList());
      received += raw.length;

      for (final j in raw) {
        final s = j['created_at'] as String?;
        final at = s == null ? null : DateTime.tryParse(s);
        if (at != null && (newestAt == null || at.isAfter(newestAt))) {
          newestAt = at;
          newest = s;
        }
      }

      if (raw.length < _pageSize) break;
      offset += raw.length;
    }

    if (newest != null) await db.setMeta(_kSalesSince, newest);
    if (received > 0) notifySalesChanged();
    return received;
  }

  // -------------------------------------------------------------------
  // SQLite -> Supabase: penjualan dengan penanda synced
  // -------------------------------------------------------------------

  /// Mengirim penjualan lokal milik [cashierId] yang belum terkirim.
  /// - Berhasil: synced = 1, harga/total diganti nilai resmi server.
  /// - Ditolak server (stok kurang, produk tidak ada, data tidak valid):
  ///   sync_error diisi dan tidak dikirim ulang otomatis.
  /// - Gangguan (offline, timeout, 5xx, 401): berhenti, dicoba lagi nanti.
  Future<({int sent, int rejected, String? error})> pushSales(
    String cashierId,
  ) async {
    final db = DbHelper.instance;
    final pending = await db.getPendingSales(cashierId);

    var sent = 0, rejected = 0;
    String? error;

    for (final sale in pending) {
      try {
        final res = await ApiClient.instance.post(
          '/sales',
          body: sale.toPushJson(),
        );
        await db.markSaleSynced(
          sale.id,
          server: res['sale'] as Map<String, dynamic>?,
        );
        sent++;
      } on ApiException catch (e) {
        if (_rejectCodes.contains(e.statusCode)) {
          await db.markSaleError(sale.id, e.message);
          rejected++;
        } else {
          error = e.message;
          break;
        }
      }
    }

    if (sent + rejected > 0) notifySalesChanged();
    return (sent: sent, rejected: rejected, error: error);
  }
}
