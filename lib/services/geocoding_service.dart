import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GeocodingException implements Exception {
  final String message;
  const GeocodingException(this.message);

  @override
  String toString() => message;
}

class GeoPlace {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;

  const GeoPlace({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

/// Pencarian tempat dan nama lokasi lewat Nominatim (OpenStreetMap).
/// Kebijakan layanan: identitas aplikasi di User-Agent, dan jangan terlalu
/// sering memanggil (maksimal sekitar 1 permintaan per detik).
class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();

  static const _host = 'nominatim.openstreetmap.org';
  static const _headers = {
    'User-Agent': 'NoirApp/1.0 (tugas kuliah Pemrograman Aplikasi Mobile)',
    'Accept': 'application/json',
  };

  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final body = await _get(
      Uri.https(_host, '/search', {
        'q': q,
        'format': 'jsonv2',
        'limit': '5',
        'accept-language': 'id',
      }),
    );
    return parseSearch(body);
  }

  /// Nama kota/daerah di sekitar titik, atau null bila tidak ditemukan.
  Future<String?> reverseName(double lat, double lng) async {
    final body = await _get(
      Uri.https(_host, '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'jsonv2',
        'zoom': '10',
        'accept-language': 'id',
      }),
    );
    return parseReverse(body);
  }

  Future<String> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const GeocodingException('Server peta tidak merespons.');
    } catch (_) {
      throw const GeocodingException('Tidak dapat terhubung ke server peta.');
    }
    if (res.statusCode != 200) {
      throw GeocodingException(
        'Server peta mengembalikan kesalahan (${res.statusCode}).',
      );
    }
    return res.body;
  }

  // ------------------------------------------------------------------
  // Parsing (statis, mudah diuji)
  // ------------------------------------------------------------------

  static String _firstPart(String text) => text.split(',').first.trim();

  static List<GeoPlace> parseSearch(String body) {
    final List<dynamic> list;
    try {
      list = jsonDecode(body) as List<dynamic>;
    } catch (_) {
      throw const GeocodingException('Format hasil pencarian tidak dikenali.');
    }
    final out = <GeoPlace>[];
    for (final item in list) {
      if (item is! Map) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;
      final display = item['display_name']?.toString() ?? '';
      var name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty) name = _firstPart(display);
      if (name.isEmpty) continue;
      out.add(
        GeoPlace(
          name: name,
          displayName: display.isEmpty ? name : display,
          latitude: lat,
          longitude: lon,
        ),
      );
    }
    return out;
  }

  static String? parseReverse(String body) {
    try {
      final map = jsonDecode(body);
      if (map is! Map || map.containsKey('error')) return null;
      final name = map['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
      final display = map['display_name']?.toString() ?? '';
      final first = _firstPart(display);
      return first.isEmpty ? null : first;
    } catch (_) {
      return null;
    }
  }
}
