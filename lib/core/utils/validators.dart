class Validators {
  Validators._();

  static final RegExp _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

  static String? required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label wajib diisi' : null;

  static String? fullName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Nama lengkap wajib diisi';
    if (s.length < 2) return 'Nama minimal 2 karakter';
    if (s.length > 50) return 'Nama maksimal 50 karakter';
    return null;
  }

  static String? username(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'Username wajib diisi';
    if (!_usernameRe.hasMatch(s)) {
      return 'Username 3-20 karakter: huruf, angka, atau underscore';
    }
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Password wajib diisi';
    if (s.length < 8) return 'Password minimal 8 karakter';
    if (s.length > 72) return 'Password maksimal 72 karakter';
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if ((v ?? '').isEmpty) return 'Konfirmasi password wajib diisi';
    if (v != original) return 'Konfirmasi password tidak sama';
    return null;
  }
}
