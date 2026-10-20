import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/auth_service.dart';

/// Dialog konfirmasi. Jika disetujui, session dihapus (secure storage dan
/// memori), lalu aplikasi kembali ke halaman login.
Future<void> confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Keluar dari akun?'),
      content: const Text(
        'Sesi Anda akan dihapus dari perangkat ini. '
        'Anda perlu login lagi untuk masuk.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Keluar'),
        ),
      ],
    ),
  );

  if (ok == true) {
    await AuthService.instance.logout();
  }
}
