import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/money_service.dart';
import 'currency_settings_screen.dart';

import '../../services/time_service.dart';
import 'time_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListenableBuilder(
            listenable: MoneyService.instance,
            builder: (context, _) => _SettingTile(
              icon: Icons.currency_exchange_rounded,
              title: 'Mata Uang',
              subtitle: 'Tampilan harga: ${MoneyService.instance.code}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CurrencySettingsScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<AppZone>(
            valueListenable: TimeService.instance.displayZone,
            builder: (context, zone, _) => _SettingTile(
              icon: Icons.schedule_rounded,
              title: 'Zona Waktu',
              subtitle: 'Waktu ditampilkan: ${TimeService.zoneName(zone)}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TimeSettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: AppColors.yellow),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
