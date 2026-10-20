import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/profile_photo_service.dart';

/// Foto profil bulat: gambar lokal pilihan pengguna, atau gambar bawaan.
class UserAvatar extends StatelessWidget {
  final double size;

  const UserAvatar({super.key, this.size = 56});

  static const String _defaultAsset = 'assets/images/default_avatar.png';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ProfilePhotoService.instance.path,
      builder: (context, photoPath, _) {
        final Widget fallback = Image.asset(
          _defaultAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            border: Border.all(color: AppColors.yellow, width: 2),
          ),
          child: ClipOval(
            child: photoPath == null
                ? fallback
                : Image.file(
                    File(photoPath),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
          ),
        );
      },
    );
  }
}
