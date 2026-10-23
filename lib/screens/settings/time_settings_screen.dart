import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/time_service.dart';

class TimeSettingsScreen extends StatefulWidget {
  const TimeSettingsScreen({super.key});

  @override
  State<TimeSettingsScreen> createState() => _TimeSettingsScreenState();
}

class _TimeSettingsScreenState extends State<TimeSettingsScreen> {
  final TimeService _time = TimeService.instance;
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _offsetLabel(AppZone z) =>
      'UTC+${TimeService.offsetMinutes(z, _now) ~/ 60}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zona Waktu')),
      body: ValueListenableBuilder<AppZone>(
        valueListenable: _time.displayZone,
        builder: (context, selected, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Pilih zona waktu untuk menampilkan jam di seluruh aplikasi: '
              'waktu input penjualan, riwayat, dan catatan blockchain.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            for (final z in AppZone.values) _option(z, selected),
            const SizedBox(height: 8),
            _example(selected),
            const SizedBox(height: 16),
            const Text(
              'Waktu input disimpan dalam UTC, sehingga tetap akurat di zona '
              'mana pun. London otomatis memakai BST (musim panas) atau GMT.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(AppZone z, AppZone selected) {
    final isSelected = z == selected;
    final wall = TimeService.toZone(_now, z);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? AppColors.yellow.withValues(alpha: 0.12)
            : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? AppColors.yellow : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isSelected ? AppColors.yellow : AppColors.textSecondary,
          ),
          title: Text(
            TimeService.zoneName(z),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _offsetLabel(z),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                TimeService.formatClock(wall),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                TimeService.abbreviation(z, _now),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          onTap: () => _time.setDisplayZone(z),
        ),
      ),
    );
  }

  Widget _example(AppZone selected) {
    final wib = TimeService.formatHm(TimeService.toZone(_now, AppZone.wib));
    final sel = TimeService.formatHm(TimeService.toZone(_now, selected));
    final abbr = TimeService.abbreviation(selected, _now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$wib WIB'),
            const Icon(Icons.arrow_forward_rounded, size: 18),
            Text(
              '$sel $abbr',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.yellow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
