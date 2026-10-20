import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../widgets/home_header.dart';
import '../../widgets/noir_logo.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const NoirLogo(width: 88)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          HomeHeader(subtitle: 'Selamat datang di Noir'),
          SizedBox(height: 24),
          Card(
            child: ListTile(
              leading:
                  Icon(Icons.shopping_bag_outlined, color: AppColors.yellow),
              title: Text('Katalog ATK'),
              subtitle: Text('Segera hadir di Sprint 2',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
