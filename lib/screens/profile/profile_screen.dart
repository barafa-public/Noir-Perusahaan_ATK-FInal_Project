import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/profile_photo_service.dart';
import '../../widgets/biometric_setting_tile.dart';
import '../../widgets/logout_dialog.dart';
import '../../widgets/user_avatar.dart';

enum _PhotoAction { gallery, camera, remove }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    final user = AuthService.instance.user;
    if (user == null || _busy) return;

    final hasPhoto = ProfilePhotoService.instance.path.value != null;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil dengan kamera'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.camera),
            ),
            if (hasPhoto)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Hapus foto',
                    style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(ctx, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;

    setState(() => _busy = true);
    try {
      switch (action) {
        case _PhotoAction.gallery:
          await ProfilePhotoService.instance.pickFromGallery(user.id);
        case _PhotoAction.camera:
          await ProfilePhotoService.instance.pickFromCamera(user.id);
        case _PhotoAction.remove:
          await ProfilePhotoService.instance.remove(user.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Tidak dapat mengambil foto. Periksa izin kamera atau galeri.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    final roleLabel =
        (user?.isInternal ?? false) ? 'User Internal' : 'Customer';

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _changePhoto,
              child: Stack(
                children: [
                  const UserAvatar(size: 104),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.black, width: 3),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.black),
                            )
                          : const Icon(Icons.edit_rounded,
                              size: 16, color: AppColors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user?.fullName ?? '-',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '@${user?.username ?? '-'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.yellow.withValues(alpha: 0.6)),
              ),
              child: Text(
                roleLabel,
                style: const TextStyle(
                    color: AppColors.yellow, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const BiometricSettingTile(),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}
