import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/navigation.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'biometric_service.dart';
import 'session_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthService extends ChangeNotifier {
  AuthService._() {
    ApiClient.instance.onUnauthorized = _onUnauthorized;
  }
  static final AuthService instance = AuthService._();

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  String? _notice;
  Timer? _expiryTimer;

  AuthStatus get status => _status;
  UserModel? get user => _user;

  /// Pesan satu kali untuk layar login (mis. "Sesi berakhir").
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// Auto-login: dipanggil sekali saat aplikasi dibuka.
  Future<void> restoreSession() async {
    final stored = await SessionService.instance.read();

    if (stored == null) {
      _setUnauthenticated();
      return;
    }
    if (stored.isExpired) {
      await SessionService.instance.clear();
      _setUnauthenticated(notice: 'Sesi berakhir. Silakan login kembali.');
      return;
    }

    _user = stored.user;
    _status = AuthStatus.authenticated;
    _scheduleExpiry(stored.expiresAt);
    notifyListeners();

    unawaited(_verifyInBackground());
  }

  /// Memastikan token masih diterima server. Jika 401, ApiClient memicu
  /// logout otomatis. Gagal karena offline diabaikan (tetap login).
  Future<void> _verifyInBackground() async {
    try {
      final res = await ApiClient.instance.get('/auth/me');
      final u = UserModel.fromJson(res['user'] as Map<String, dynamic>);
      if (_status == AuthStatus.authenticated) {
        _user = u;
        notifyListeners();
      }
    } on ApiException {
      // 401 sudah ditangani onUnauthorized; error lain diabaikan.
    }
  }

  Future<void> login(String username, String password) async {
    final res = await ApiClient.instance.post(
      '/auth/login',
      auth: false,
      body: {'username': username.trim().toLowerCase(), 'password': password},
    );
    await _startSession(res);
  }

  Future<void> register({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final res = await ApiClient.instance.post(
      '/auth/register',
      auth: false,
      body: {
        'full_name': fullName.trim(),
        'username': username.trim().toLowerCase(),
        'password': password,
      },
    );
    await _startSession(res);
  }

  /// Login ulang memakai kredensial tersimpan (dipanggil SETELAH biometrik lolos).
  Future<void> loginWithStoredCredentials() async {
    final creds = await BiometricService.instance.readCredentials();
    if (creds == null) {
      throw const ApiException('Login biometrik belum diaktifkan.');
    }
    try {
      await login(creds.username, creds.password);
    } on ApiException catch (e) {
      if (e.code == 'BAD_CREDENTIALS') {
        await BiometricService.instance.disable();
        throw const ApiException(
          'Password berubah. Login dengan password, lalu aktifkan biometrik lagi.',
        );
      }
      rethrow;
    }
  }

  /// Verifikasi password ke server, lalu simpan untuk login biometrik.
  Future<void> enableBiometric(String password) async {
    final u = _user;
    if (u == null) throw const ApiException('Belum login.');
    try {
      await ApiClient.instance.post(
        '/auth/login',
        auth: false,
        body: {'username': u.username, 'password': password},
      );
    } on ApiException catch (e) {
      if (e.code == 'BAD_CREDENTIALS') {
        throw const ApiException('Password salah.');
      }
      rethrow;
    }
    await BiometricService.instance.enable(
      username: u.username,
      password: password,
    );
  }

  Future<void> logout() async {
    await SessionService.instance.clear();
    _setUnauthenticated();
  }

  Future<void> _startSession(Map<String, dynamic> res) async {
    final user = UserModel.fromJson(res['user'] as Map<String, dynamic>);
    final expiresAt = DateTime.parse(res['expires_at'] as String);

    await SessionService.instance.save(
      token: res['token'] as String,
      expiresAt: expiresAt,
      user: user,
    );

    _user = user;
    _notice = null;
    _status = AuthStatus.authenticated;
    _scheduleExpiry(expiresAt);
    notifyListeners();
  }

  void _scheduleExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final remaining = expiresAt.toUtc().difference(DateTime.now().toUtc());
    _expiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _forceLogout('Sesi berakhir. Silakan login kembali.');
    });
  }

  void _onUnauthorized() {
    if (_status == AuthStatus.authenticated) {
      _forceLogout('Sesi berakhir. Silakan login kembali.');
    }
  }

  Future<void> _forceLogout(String message) async {
    await SessionService.instance.clear();
    _setUnauthenticated(notice: message);
  }

  void _setUnauthenticated({String? notice}) {
    _expiryTimer?.cancel();
    _user = null;
    _notice = notice;
    _status = AuthStatus.unauthenticated;
    // Tutup halaman yang masih terbuka di atas halaman utama.
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    notifyListeners();
  }
}
