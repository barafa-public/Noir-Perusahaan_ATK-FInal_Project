import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../widgets/home_header.dart';
import '../../widgets/noir_logo.dart';

class InternalHomeScreen extends StatelessWidget {
  const InternalHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const NoirLogo(width: 88)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          HomeHeader(subtitle: 'Dashboard User Internal'),
          SizedBox(height: 24),
          Card(
            child: ListTile(
              leading:
                  Icon(Icons.inventory_2_outlined, color: AppColors.yellow),
              title: Text('Ringkasan stok'),
              subtitle: Text('Segera hadir di Sprint 3',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
