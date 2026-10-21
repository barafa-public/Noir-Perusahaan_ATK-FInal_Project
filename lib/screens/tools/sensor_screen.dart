import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/sensor_service.dart';
import '../../services/time_service.dart';

class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen>
    with WidgetsBindingObserver {
  final SensorService _sensors = SensorService();
  StreamSubscription<void>? _shakeSub;
  Timer? _firstCapture;

  SensorSnapshot? _snapshot;
  bool _shakeEnabled = true;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sensors.start();
    _shakeSub = _sensors.shakes.listen((_) => _onShake());
    // Data pertama diambil otomatis setelah sensor sempat mengirim nilai.
    _firstCapture = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _snapshot == null) _capture();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _firstCapture?.cancel();
    _shakeSub?.cancel();
    _sensors.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hemat baterai: sensor berhenti saat aplikasi di latar belakang.
    if (state == AppLifecycleState.resumed) {
      _sensors.start();
    } else if (state == AppLifecycleState.paused) {
      _sensors.stop();
    }
  }

  void _capture() => setState(() => _snapshot = _sensors.capture());

  Future<void> _onShake() async {
    if (!mounted || _dialogOpen || !_shakeEnabled) return;
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ambil ulang data?'),
        content: const Text(
          'Goyangan terdeteksi. Data sensor yang terambil sebelumnya akan '
          'diganti dengan data terbaru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ambil ulang'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true && mounted) {
      _capture();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data sensor diambil ulang.')),
      );
    }
  }

  String _stamp(DateTime at) {
    final utc = at.toUtc();
    final zone = TimeService.instance.displayZone.value;
    return '${TimeService.formatClock(TimeService.toZone(utc, zone))} '
        '${TimeService.abbreviation(zone, utc)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SensorCard(
            title: 'Accelerometer',
            unit: 'm/s²',
            range: 20,
            reading: _sensors.accel,
            error: _sensors.accelError,
            footer: (r) => 'Total ${r.magnitude.toStringAsFixed(2)} m/s² '
                '(${(r.magnitude / ShakeDetector.gravity).toStringAsFixed(2)} g)',
          ),
          const SizedBox(height: 16),
          _SensorCard(
            title: 'Gyroscope',
            unit: 'rad/s',
            range: 10,
            reading: _sensors.gyro,
            error: _sensors.gyroError,
            footer: (r) => 'Total ${r.magnitude.toStringAsFixed(2)} rad/s',
          ),
          const SizedBox(height: 16),
          _snapshotCard(),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              value: _shakeEnabled,
              onChanged: (v) => setState(() {
                _shakeEnabled = v;
                _sensors.shakeEnabled = v;
              }),
              title: const Text('Goyang untuk ambil ulang'),
              subtitle: const Text(
                'Goyang perangkat dua kali, lalu konfirmasi pengambilan ulang.',
              ),
              activeThumbColor: AppColors.yellow,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Ambil ulang data'),
          ),
        ],
      ),
    );
  }

  Widget _snapshotCard() {
    final s = _snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Data terambil',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (s == null)
              const Text(
                'Belum ada data.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else ...[
              _line('Waktu', _stamp(s.takenAt)),
              _line('Accelerometer', _xyz(s.accel)),
              _line('Gyroscope', _xyz(s.gyro)),
              _line('Puncak accelerometer',
                  '${s.peakAccel.toStringAsFixed(2)} m/s²'),
              _line(
                  'Puncak gyroscope', '${s.peakGyro.toStringAsFixed(2)} rad/s'),
            ],
          ],
        ),
      ),
    );
  }

  String _xyz(SensorReading? r) => r == null
      ? '-'
      : 'x ${r.x.toStringAsFixed(2)}  y ${r.y.toStringAsFixed(2)}  '
          'z ${r.z.toStringAsFixed(2)}';

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _SensorCard extends StatelessWidget {
  final String title;
  final String unit;
  final double range;
  final ValueNotifier<SensorReading?> reading;
  final ValueNotifier<String?> error;
  final String Function(SensorReading) footer;

  const _SensorCard({
    required this.title,
    required this.unit,
    required this.range,
    required this.reading,
    required this.error,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (context, err, _) {
                if (err != null) {
                  return Text(
                    err,
                    style: const TextStyle(color: AppColors.error),
                  );
                }
                return ValueListenableBuilder<SensorReading?>(
                  valueListenable: reading,
                  builder: (context, r, _) {
                    if (r == null) {
                      return const Text(
                        'Menunggu data sensor...',
                        style: TextStyle(color: AppColors.textSecondary),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AxisRow(
                            label: 'X', value: r.x, range: range, unit: unit),
                        _AxisRow(
                            label: 'Y', value: r.y, range: range, unit: unit),
                        _AxisRow(
                            label: 'Z', value: r.z, range: range, unit: unit),
                        const SizedBox(height: 6),
                        Text(
                          footer(r),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  final String label;
  final double value;
  final double range;
  final String unit;

  const _AxisRow({
    required this.label,
    required this.value,
    required this.range,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.yellow,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (value.abs() / range).clamp(0.0, 1.0),
                minHeight: 8,
                color: AppColors.yellow,
                backgroundColor: AppColors.border,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              '${value.toStringAsFixed(2)} $unit',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
