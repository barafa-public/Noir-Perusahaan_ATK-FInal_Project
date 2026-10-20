import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricResult {
  final bool success;

  /// null saat gagal = pengguna membatalkan (tidak perlu pesan error).
  final String? message;

  const BiometricResult.ok() : success = true, message = null;
  const BiometricResult.fail([this.message]) : success = false;
}

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kUser = 'bio_username';
  static const _kPass = 'bio_password';

  final LocalAuthentication _auth = LocalAuthentication();

  /// True jika perangkat mendukung dan sudah ada sidik jari/wajah terdaftar.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return ok ? const BiometricResult.ok() : const BiometricResult.fail();
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          return const BiometricResult.fail(
            'Terlalu banyak percobaan. Gunakan password.',
          );
        case 'NotEnrolled':
        case 'NotAvailable':
        case 'PasscodeNotSet':
          return const BiometricResult.fail(
            'Biometrik belum diatur di perangkat. Gunakan password.',
          );
        default:
          return const BiometricResult.fail(
            'Autentikasi biometrik gagal. Gunakan password.',
          );
      }
    }
  }

  // ---- Kredensial untuk login biometrik (terenkripsi di secure storage) ----

  Future<String?> get enabledUsername async {
    try {
      return await _storage.read(key: _kUser);
    } catch (_) {
      return null;
    }
  }

  Future<void> enable({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
  }

  Future<({String username, String password})?> readCredentials() async {
    try {
      final u = await _storage.read(key: _kUser);
      final p = await _storage.read(key: _kPass);
      if (u == null || p == null) return null;
      return (username: u, password: p);
    } catch (_) {
      return null;
    }
  }

  Future<void> disable() async {
    try {
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kPass);
    } catch (_) {}
  }
}
