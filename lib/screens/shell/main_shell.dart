import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/noir_logo.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;

    return Scaffold(
      appBar: AppBar(title: const NoirLogo(width: 88)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Halo, ${user?.fullName ?? '-'}',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('@${user?.username ?? '-'}  •  role: ${user?.role ?? '-'}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => AuthService.instance.logout(),
              child: const Text('Logout (sementara)'),
            ),
          ],
        ),
      ),
    );
  }
}
