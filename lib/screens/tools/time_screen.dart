import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/time_service.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  Timer? _ticker;
  late AppZone _source;
  late DateTime _wall; // waktu dinding di zona sumber (berflag UTC)

  @override
  void initState() {
    super.initState();
    _source = TimeService.instance.displayZone.value;
    _wall = TimeService.toZone(DateTime.now().toUtc(), _source);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_wall.year, _wall.month, _wall.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _wall = DateTime.utc(
        picked.year,
        picked.month,
        picked.day,
        _wall.hour,
        _wall.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute),
    );
    if (picked == null) return;
    setState(() {
      _wall = DateTime.utc(
        _wall.year,
        _wall.month,
        _wall.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _useNow() => setState(() {
        _wall = TimeService.toZone(DateTime.now().toUtc(), _source);
      });

  @override
  Widget build(BuildContext context) {
    final nowUtc = DateTime.now().toUtc();
    final displayZone = TimeService.instance.displayZone.value;
    final sourceUtc = TimeService.toUtc(_wall, _source);

    return Scaffold(
      appBar: AppBar(title: const Text('Konversi Waktu')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _Heading('Waktu sekarang'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: AppZone.values.map((z) {
                  final wall = TimeService.toZone(nowUtc, z);
                  return _ZoneRow(
                    title: TimeService.zoneName(z),
                    abbreviation: TimeService.abbreviation(z, nowUtc),
                    time: TimeService.formatClock(wall),
                    date: TimeService.formatDate(wall),
                    highlight: z == displayZone,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _Heading('Zona tampilan aplikasi'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: AppZone.values
                .map(
                  (z) => ChoiceChip(
                    label: Text(TimeService.abbreviation(z, nowUtc)),
                    selected: displayZone == z,
                    onSelected: (_) async {
                      await TimeService.instance.setDisplayZone(z);
                      if (mounted) setState(() {});
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          const Text(
            'Waktu pada Riwayat Penjualan mengikuti zona ini.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 24),
          const _Heading('Konversi waktu'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: AppZone.values
                .map(
                  (z) => ChoiceChip(
                    label:
                        Text('Dari ${TimeService.abbreviation(z, sourceUtc)}'),
                    selected: _source == z,
                    onSelected: (_) => setState(() => _source = z),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(
                    '${_wall.day}/${_wall.month}/${_wall.year}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(
                    '${_wall.hour.toString().padLeft(2, '0')}.'
                    '${_wall.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _useNow,
              child: const Text('Gunakan waktu sekarang'),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: AppZone.values.map((z) {
                  final wall = TimeService.toZone(sourceUtc, z);
                  return _ZoneRow(
                    title: TimeService.zoneName(z),
                    abbreviation: TimeService.abbreviation(z, sourceUtc),
                    time: TimeService.formatDateTime(wall).split(', ').last,
                    date: TimeService.formatDate(wall),
                    highlight: z == _source,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      );
}

class _ZoneRow extends StatelessWidget {
  final String title;
  final String abbreviation;
  final String time;
  final String date;
  final bool highlight;

  const _ZoneRow({
    required this.title,
    required this.abbreviation,
    required this.time,
    required this.date,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: highlight ? AppColors.yellow : AppColors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                abbreviation,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
