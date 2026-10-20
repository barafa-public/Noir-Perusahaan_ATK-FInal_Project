import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user_model.dart';

class StoredSession {
  final String token;
  final DateTime expiresAt;
  final UserModel user;

  const StoredSession({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  bool get isExpired => !DateTime.now().toUtc().isBefore(expiresAt.toUtc());
}

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kToken = 'session_token';
  static const _kExpires = 'session_expires_at';
  static const _kUser = 'session_user';

  String? _token;

  /// Token di memori, dipakai ApiClient pada setiap request.
  String? get token => _token;

  Future<void> save({
    required String token,
    required DateTime expiresAt,
    required UserModel user,
  }) async {
    _token = token;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(
        key: _kExpires, value: expiresAt.toUtc().toIso8601String());
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
  }

  Future<StoredSession?> read() async {
    try {
      final token = await _storage.read(key: _kToken);
      final expires = await _storage.read(key: _kExpires);
      final user = await _storage.read(key: _kUser);
      if (token == null || expires == null || user == null) return null;

      final session = StoredSession(
        token: token,
        expiresAt: DateTime.parse(expires),
        user: UserModel.fromJson(jsonDecode(user) as Map<String, dynamic>),
      );
      _token = token;
      return session;
    } catch (_) {
      // Data rusak atau kunci enkripsi berubah: anggap tidak ada sesi.
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    _token = null;
    try {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kExpires);
      await _storage.delete(key: _kUser);
    } catch (_) {}
  }
}
