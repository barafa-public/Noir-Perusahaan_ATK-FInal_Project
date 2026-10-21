import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_colors.dart';
import '../../services/location_service.dart';
import '../../services/time_service.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Position? _pos;
  StoreLocation _store = LocationService.defaultStore;
  bool _loading = true;
  LocationException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = await LocationService.instance.loadStore();
    try {
      final pos = await LocationService.instance.currentPosition();
      if (!mounted) return;
      setState(() {
        _store = store;
        _pos = pos;
        _loading = false;
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _store = store;
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _setStoreHere() async {
    final pos = _pos;
    if (pos == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jadikan lokasi toko?'),
        content: const Text(
          'Lokasi Anda saat ini akan dipakai sebagai lokasi toko untuk '
          'menghitung jarak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, jadikan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocationService.instance.saveStore(pos.latitude, pos.longitude);
    final store = await LocationService.instance.loadStore();
    if (mounted) setState(() => _store = store);
  }

  Future<void> _resetStore() async {
    await LocationService.instance.resetStore();
    final store = await LocationService.instance.loadStore();
    if (mounted) setState(() => _store = store);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lokasi & Jarak'),
        actions: [
          IconButton(
            tooltip: 'Perbarui lokasi',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final pos = _pos;

    if (pos == null) {
      if (_loading) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.yellow),
              SizedBox(height: 16),
              Text(
                'Mencari lokasi...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }
      return _errorView(_error);
    }

    final meters = LocationService.distanceMeters(pos, _store);
    final taken = TimeService.instance.formatIso(
      pos.timestamp.toUtc().toIso8601String(),
    );
    final isCustomStore =
        _store.latitude != LocationService.defaultStore.latitude ||
            _store.longitude != LocationService.defaultStore.longitude;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_loading) ...[
          const LinearProgressIndicator(color: AppColors.yellow),
          const SizedBox(height: 12),
        ],
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${_error!.message}\nMenampilkan lokasi terakhir.',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jarak ke toko',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  LocationService.formatDistance(meters),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.yellow,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Jarak garis lurus',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Lokasi Anda',
          rows: [
            _Row('Latitude', pos.latitude.toStringAsFixed(6)),
            _Row('Longitude', pos.longitude.toStringAsFixed(6)),
            _Row('Akurasi', '± ${pos.accuracy.round()} m'),
            _Row('Diambil', taken),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: _store.name,
          rows: [
            _Row('Latitude', _store.latitude.toStringAsFixed(6)),
            _Row('Longitude', _store.longitude.toStringAsFixed(6)),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _setStoreHere,
          icon: const Icon(Icons.store_rounded),
          label: const Text('Jadikan lokasi saya sebagai lokasi toko'),
        ),
        if (isCustomStore)
          TextButton(
            onPressed: _resetStore,
            child: const Text('Kembalikan lokasi toko bawaan'),
          ),
      ],
    );
  }

  Widget _errorView(LocationException? e) {
    final type = e?.type;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded,
                size: 56, color: AppColors.yellow),
            const SizedBox(height: 16),
            Text(
              e?.message ?? 'Lokasi tidak tersedia.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (type == LocationFailure.serviceOff)
              FilledButton(
                onPressed: Geolocator.openLocationSettings,
                child: const Text('Buka pengaturan lokasi'),
              ),
            if (type == LocationFailure.deniedForever)
              FilledButton(
                onPressed: Geolocator.openAppSettings,
                child: const Text('Buka pengaturan aplikasi'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      r.label,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    Flexible(
                      child: Text(
                        r.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
