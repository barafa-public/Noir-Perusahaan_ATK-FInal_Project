import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/product_model.dart';

/// Pembungkus flutter_local_notifications. Hanya satu jenis notifikasi:
/// produk yang stoknya mencapai batas minimum (PBI-09.2).
/// Semua pemanggilan aman: kegagalan hanya dicatat, tidak membuat aplikasi crash.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'low_stock';
  static const _channelName = 'Stok menipis';
  static const _channelDesc =
      'Pemberitahuan saat stok produk mencapai batas minimum';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Menyiapkan plugin. Aman dipanggil berulang.
  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifikasi gagal diinisialisasi: $e');
    }
  }

  /// Android 13+ meminta izin POST_NOTIFICATIONS saat runtime.
  /// Mengembalikan true jika diizinkan (atau tidak perlu izin).
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('Izin notifikasi gagal diminta: $e');
      return false;
    }
  }

  /// Menampilkan satu notifikasi untuk produk yang BARU menipis.
  /// Satu produk: nama dan sisa stok. Beberapa produk: ringkasan berisi daftar.
  Future<void> showLowStock(List<ProductModel> products) async {
    if (products.isEmpty) return;
    if (!_ready) await init();
    if (!_ready) return;

    final String title;
    final String body;
    InboxStyleInformation? style;

    if (products.length == 1) {
      final p = products.first;
      title = p.isOutOfStock ? 'Stok habis' : 'Stok menipis';
      body = '${p.name}: sisa ${p.stock} (minimum ${p.minStock})';
    } else {
      title = '${products.length} produk stoknya menipis';
      final lines = products
          .take(6)
          .map((p) => '${p.name}: sisa ${p.stock}/${p.minStock}')
          .toList();
      if (products.length > 6) {
        lines.add('dan ${products.length - 6} produk lainnya');
      }
      body = lines.first;
      style = InboxStyleInformation(
        lines,
        contentTitle: title,
        summaryText: 'Stok menipis',
      );
    }

    try {
      await _plugin.show(
        id: _newId(),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: style,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Notifikasi gagal ditampilkan: $e');
    }
  }

  /// ID unik per notifikasi agar yang lama tidak tertimpa.
  int _newId() => (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7fffffff;
}
