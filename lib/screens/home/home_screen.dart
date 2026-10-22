import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/sync_service.dart';
import '../../widgets/home_header.dart';
import '../../widgets/noir_logo.dart';
import '../../widgets/stock_summary_card.dart';
import '../sales/sale_form_screen.dart';
import '../sales/sales_history_screen.dart';
import '../../widgets/tools_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const NoirLogo(width: 88)),
      body: RefreshIndicator(
        color: AppColors.yellow,
        backgroundColor: AppColors.surface,
        onRefresh: () => SyncService.instance.syncAll(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const HomeHeader(subtitle: 'Dashboard Admin'),
            const SizedBox(height: 24),
            const StockSummaryCard(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SaleFormScreen())),
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('Catat Penjualan'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              ),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Riwayat Penjualan'),
            ),
            const SizedBox(height: 28),
            const ToolsSection(),
          ],
        ),
      ),
    );
  }
}
