import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foto profil lokal, disimpan per akun di penyimpanan aplikasi.
class ProfilePhotoService {
  ProfilePhotoService._();
  static final ProfilePhotoService instance = ProfilePhotoService._();

  /// Path foto akun yang sedang login; null berarti memakai gambar bawaan.
  final ValueNotifier<String?> path = ValueNotifier<String?>(null);

  final ImagePicker _picker = ImagePicker();

  String _key(String userId) => 'avatar_path_$userId';

  /// Dipanggil saat halaman utama dibuka, untuk memuat foto akun ini.
  Future<void> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(userId));
    if (saved != null && await File(saved).exists()) {
      path.value = saved;
    } else {
      if (saved != null) await prefs.remove(_key(userId));
      path.value = null;
    }
  }

  Future<bool> pickFromGallery(String userId) =>
      _pick(userId, ImageSource.gallery);

  Future<bool> pickFromCamera(String userId) =>
      _pick(userId, ImageSource.camera);

  /// Mengembalikan false jika pengguna membatalkan pemilihan.
  Future<bool> _pick(String userId, ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return false;

    // Salin ke penyimpanan aplikasi: file bawaan picker berada di cache
    // sementara dan bisa dihapus sistem.
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(picked.path).copy(dest);

    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_key(userId));
    await prefs.setString(_key(userId), dest);
    path.value = dest;

    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    return true;
  }

  Future<void> remove(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_key(userId));
    await prefs.remove(_key(userId));
    path.value = null;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}
