import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:math' as math;

enum LocationFailure { serviceOff, denied, deniedForever, timeout, unknown }

class LocationException implements Exception {
  final LocationFailure type;
  final String message;
  const LocationException(this.type, this.message);

  @override
  String toString() => message;
}

class StoreLocation {
  final String name;
  final double latitude;
  final double longitude;

  const StoreLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Titik contoh (Yogyakarta). Ganti lewat tombol di layar Lokasi,
  /// atau ubah nilainya di sini.
  static const StoreLocation defaultStore = StoreLocation(
    name: 'Toko Noir',
    latitude: -7.7828,
    longitude: 110.3671,
  );

  static const _latKey = 'store_lat';
  static const _lngKey = 'store_lng';

  Future<StoreLocation> loadStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_latKey);
      final lng = prefs.getDouble(_lngKey);
      if (lat != null && lng != null) {
        return StoreLocation(
          name: defaultStore.name,
          latitude: lat,
          longitude: lng,
        );
      }
    } catch (_) {}
    return defaultStore;
  }

  Future<void> saveStore(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_latKey, lat);
    await prefs.setDouble(_lngKey, lng);
  }

  Future<void> resetStore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_latKey);
    await prefs.remove(_lngKey);
  }

  /// Memeriksa layanan dan izin lokasi, lalu mengambil posisi saat ini.
  /// Melempar [LocationException] dengan pesan yang siap ditampilkan.
  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.serviceOff,
        'Layanan lokasi (GPS) di perangkat sedang mati.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.denied,
        'Izin lokasi ditolak. Izin dibutuhkan untuk menghitung jarak ke toko.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.deniedForever,
        'Izin lokasi ditolak permanen. Aktifkan lewat pengaturan aplikasi.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw const LocationException(
        LocationFailure.timeout,
        'Lokasi belum ditemukan. Coba di tempat terbuka lalu ulangi.',
      );
    } catch (_) {
      throw const LocationException(
        LocationFailure.unknown,
        'Gagal mengambil lokasi perangkat.',
      );
    }
  }

  static double distanceMeters(Position p, StoreLocation s) =>
      Geolocator.distanceBetween(
        p.latitude,
        p.longitude,
        s.latitude,
        s.longitude,
      );

  /// Jarak garis lurus (rumus haversine) antara dua titik, dalam meter.
  static double haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371008.8; // meter
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(a.toDouble()));
  }

  /// 850 -> "850 m"; 12345 -> "12,35 km"
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = (meters / 1000).toStringAsFixed(meters < 100000 ? 2 : 0);
    return '${km.replaceAll('.', ',')} km';
  }
}
