import '../models/product_model.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'db_helper.dart';

class SyncReport {
  final int productsReceived;
  final int salesSent;
  final int salesRejected;
  final String? error;

  const SyncReport({
    this.productsReceived = 0,
    this.salesSent = 0,
    this.salesRejected = 0,
    this.error,
  });

  @override
  String toString() =>
      'SyncReport(produk: $productsReceived, terkirim: $salesSent, '
      'ditolak: $salesRejected, error: $error)';
}

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _kProductsSince = 'products_last_sync';
  static const _pageSize = 200;

  /// Status HTTP yang berarti "penjualan INI ditolak" (bukan gangguan sementara).
  static const _rejectCodes = {404, 409, 422};

  Future<SyncReport>? _running;

  /// Kirim penjualan tertunda (internal), lalu tarik perubahan produk.
  /// Aman dipanggil berulang: panggilan yang tumpang tindih memakai hasil yang sama.
  /// Tidak melempar error; hasilnya ada di [SyncReport.error].
  Future<SyncReport> syncAll() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    final user = AuthService.instance.user;
    if (user == null) return const SyncReport(error: 'Belum login.');

    var sent = 0, rejected = 0, received = 0;
    String? error;

    // Kirim dulu, baru tarik produk, agar stok yang terambil sudah
    // memperhitungkan penjualan yang baru dikirim.
    if (user.isInternal) {
      final push = await pushSales(user.id);
      sent = push.sent;
      rejected = push.rejected;
      error = push.error;
    }

    try {
      received = await syncProducts();
    } on ApiException catch (e) {
      error ??= e.message;
    }

    return SyncReport(
      productsReceived: received,
      salesSent: sent,
      salesRejected: rejected,
      error: error,
    );
  }

  // -------------------------------------------------------------------
  // PBI-04.3: Supabase -> SQLite (cache katalog)
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
    return received;
  }

  // -------------------------------------------------------------------
  // PBI-04.4: SQLite -> Supabase (penjualan, dengan penanda synced)
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
    return (sent: sent, rejected: rejected, error: error);
  }
}
