import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../screens/tools/location_screen.dart';
import '../screens/tools/sensor_screen.dart';

import '../screens/tools/blockchain_screen.dart';
import '../screens/tools/ai_chat_screen.dart';
import '../screens/tools/game_screen.dart';
import '../screens/tools/forecast_screen.dart';

class _Tool {
  final String label;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;

  const _Tool(this.label, this.subtitle, this.icon, this.builder);
}

/// Daftar fitur pendukung. Batch berikutnya cukup menambah satu entri di sini.
final List<_Tool> _tools = [
  _Tool(
    'Lokasi',
    'Jarak ke tujuan',
    Icons.location_on_rounded,
    (_) => const LocationScreen(),
  ),
  _Tool(
    'Sensor',
    'Accelerometer, gyroscope',
    Icons.sensors_rounded,
    (_) => const SensorScreen(),
  ),
  _Tool(
    'Blockchain',
    'Hash penjualan',
    Icons.link_rounded,
    (_) => const BlockchainScreen(),
  ),
  _Tool(
    'Asisten AI',
    'Tanya soal stok',
    Icons.smart_toy_rounded,
    (_) => const AiChatScreen(),
  ),
  _Tool(
    'Prediksi Stok',
    'Rekomendasi restock',
    Icons.insights_rounded,
    (_) => const ForecastScreen(),
  ),
  _Tool(
    'Mini Game',
    'Tebak harga ATK',
    Icons.sports_esports_rounded,
    (_) => const GameScreen(),
  ),
];

class ToolsSection extends StatelessWidget {
  const ToolsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alat & Fitur',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: _tools.map((t) => _ToolTile(tool: t)).toList(),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  final _Tool tool;
  const _ToolTile({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: tool.builder)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(tool.icon, color: AppColors.yellow, size: 28),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
