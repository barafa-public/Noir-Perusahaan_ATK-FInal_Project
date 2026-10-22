import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import 'session_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _timeout = Duration(seconds: 20);

  /// Dipanggil saat request ber-token ditolak server (401).
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    Duration? timeout,
  }) =>
      _send('POST', path, body: body, auth: auth, timeout: timeout);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool auth,
    Duration? timeout,
  }) async {
    if (!Env.isConfigured) {
      throw const ApiException(
          'BACKEND_URL / BACKEND_PUBLISHABLE_KEY belum diatur di .env');
    }

    final uri = Uri.parse('${Env.backendUrl}$path');
    final headers = <String, String>{
      'apikey': Env.publishableKey,
      'Content-Type': 'application/json',
    };
    if (auth) {
      final t = SessionService.instance.token;
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }

    http.Response res;
    try {
      final request = method == 'GET'
          ? http.get(uri, headers: headers)
          : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await request.timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw const ApiException('Server tidak merespons. Coba lagi.');
    } catch (_) {
      throw const ApiException('Tidak dapat terhubung ke server.');
    }

    var data = <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (auth && res.statusCode == 401) onUnauthorized?.call();

    throw ApiException(
      (data['error'] as String?) ?? 'Terjadi kesalahan (${res.statusCode})',
      statusCode: res.statusCode,
      code: data['code'] as String?,
    );
  }
}
