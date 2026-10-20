import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../widgets/noir_logo.dart';
import '../../widgets/role_gate.dart';
import '../profile/profile_screen.dart';

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
            Text(
              'Halo, ${user?.fullName ?? '-'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '@${user?.username ?? '-'}  •  role: ${user?.role ?? '-'}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: const Text('Buka Profil'),
            ),
            const SizedBox(height: 12),
            // Demo RoleGate: hanya terlihat oleh User internal.
            const RoleGate(
              allowed: [Roles.internal],
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.yellow,
                  ),
                  title: Text('Menu khusus User internal'),
                ),
              ),
            ),
            // Demo RoleGate: hanya terlihat oleh Customer.
            const RoleGate(
              allowed: [Roles.customer],
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.yellow,
                  ),
                  title: Text('Menu khusus Customer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
