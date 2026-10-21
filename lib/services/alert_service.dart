import 'dart:async';

import 'auth_service.dart';
import 'db_helper.dart';
import 'notification_service.dart';
import 'product_service.dart';

/// Aturan kapan notifikasi dimunculkan. Semuanya berbasis data yang baru
/// disinkronkan atau diubah di aplikasi; tidak ada proses latar belakang.
class AlertService {
  AlertService._();

  static final AlertService instance = AlertService._();

  bool _started = false;
  bool _checkingStock = false;
  bool _stockAgain = false;

  /// Dipanggil sekali setelah login (dari MainShell): menyiapkan notifikasi,
  /// meminta izin, dan mulai memantau perubahan stok.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();

    // Berubah setiap kali sinkronisasi produk, penjualan dicatat, atau
    // produk disimpan; jadi pengecekan stok selalu mengikuti data terbaru.
    ProductService.instance.changes.addListener(_onProductsChanged);
    await checkLowStock();
  }

  void _onProductsChanged() => unawaited(checkLowStock());

  // ------------------------------------------------------------------
  // PBI-09.2: stok <= batas minimum (User internal)
  // ------------------------------------------------------------------

  /// Memberi tahu produk yang BARU menjadi menipis. Penanda di tabel
  /// low_stock_alerts mencegah notifikasi berulang; penanda dihapus saat stok
  /// pulih di atas minimum, sehingga turun lagi nanti akan diberitahukan lagi.
  /// Memakai stok efektif (sudah dikurangi penjualan lokal yang belum terkirim).
  Future<void> checkLowStock() async {
    final user = AuthService.instance.user;
    if (user == null || !user.isInternal) return;

    if (_checkingStock) {
      _stockAgain = true;
      return;
    }

    _checkingStock = true;

    try {
      do {
        _stockAgain = false;
        await _checkLowStockOnce();
      } while (_stockAgain);
    } finally {
      _checkingStock = false;
    }
  }

  Future<void> _checkLowStockOnce() async {
    final db = DbHelper.instance;
    final low = await db.getLowStockProducts(limit: 1000);
    final alerted = await db.getAlertedProductIds();
    final lowIds = low.map((p) => p.id).toSet();

    // Stok sudah pulih (atau produk dinonaktifkan):
    // izinkan notifikasi lagi.
    for (final id in alerted.where((id) => !lowIds.contains(id))) {
      await db.clearProductAlert(id);
    }

    final fresh = low.where((p) => !alerted.contains(p.id)).toList();

    if (fresh.isEmpty) return;

    // Tandai dulu, baru tampilkan: jika tampil gagal,
    // tidak diulang terus-menerus.
    await db.markProductsAlerted(fresh.map((p) => p.id).toList());

    await NotificationService.instance.showLowStock(fresh);
  }
}
