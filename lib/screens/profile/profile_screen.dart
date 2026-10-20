import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/biometric_setting_tile.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            user?.fullName ?? '-',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '@${user?.username ?? '-'}  •  ${user?.role ?? '-'}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          const BiometricSettingTile(),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => AuthService.instance.logout(),
            child: const Text('Logout (sementara)'),
          ),
        ],
      ),
    );
  }
}
