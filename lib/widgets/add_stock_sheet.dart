import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_colors.dart';
import '../models/product_model.dart';
import '../services/api_client.dart';
import '../services/product_service.dart';
import '../services/sensor_service.dart';

class StockInRules {
  StockInRules._();

  static const int maxQty = 1000;
  static const List<int> steps = [1, 5, 10];

  static int clampQty(int v) => v < 1 ? 1 : (v > maxQty ? maxQty : v);
}

/// Lembar "Tambah stok". Mengembalikan produk terbaru dari server bila
/// berhasil, atau null bila dibatalkan. [initialQty] mengisi jumlah awal
/// (mis. dari saran restock).
Future<ProductModel?> showAddStockSheet(
  BuildContext context,
  ProductModel product, {
  int? initialQty,
}) {
  return showModalBottomSheet<ProductModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _AddStockSheet(product: product, initialQty: initialQty),
  );
}

class _AddStockSheet extends StatefulWidget {
  final ProductModel product;
  final int? initialQty;

  const _AddStockSheet({required this.product, this.initialQty});

  @override
  State<_AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<_AddStockSheet> {
  final SensorService _sensors = SensorService();
  StreamSubscription<int>? _twistSub;
  StreamSubscription<void>? _shakeSub;

  late int _qty;
  int _step = 1;
  bool _sensorOn = true;
  bool _inverted = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = StockInRules.clampQty(widget.initialQty ?? 1);
    _sensors.twistEnabled = true;
    _twistSub = _sensors.twists.listen(_onTwist);
    _shakeSub = _sensors.shakes.listen((_) => _onShake());
    _sensors.start();
  }

  @override
  void dispose() {
    _twistSub?.cancel();
    _shakeSub?.cancel();
    _sensors.dispose();
    super.dispose();
  }

  void _change(int delta) {
    setState(() => _qty = StockInRules.clampQty(_qty + delta));
  }

  void _onTwist(int dir) {
    if (!_sensorOn || _busy || !mounted) return;
    HapticFeedback.selectionClick();
    _change((_inverted ? -dir : dir) * _step);
  }

  void _onShake() {
    if (!_sensorOn || _busy || !mounted) return;
    HapticFeedback.mediumImpact();
    _submit();
  }

  void _setSensorOn(bool v) {
    setState(() => _sensorOn = v);
    _sensors.shakeEnabled = v;
    _sensors.twistEnabled = v;
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ProductService.instance.addStock(
        widget.product.id,
        _qty,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // Tanpa kode status = jaringan/timeout: penambahan mungkin sudah masuk.
        _error = e.statusCode == null
            ? '${e.message} Periksa stok produk sebelum mencoba lagi, '
                'karena penambahan mungkin sudah masuk.'
            : e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final initial = widget.initialQty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tambah stok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              p.name,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  onPressed: _busy ? null : () => _change(-_step),
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    '$_qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: AppColors.yellow,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: _busy ? null : () => _change(_step),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            Text(
              'Stok ${p.stock} → ${p.stock + _qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final s in StockInRules.steps)
                  ChoiceChip(
                    label: Text('Langkah $s'),
                    selected: _step == s,
                    onSelected: _busy ? null : (_) => setState(() => _step = s),
                  ),
              ],
            ),
            if (initial != null && _qty != StockInRules.clampQty(initial))
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _qty = StockInRules.clampQty(initial),
                        ),
                child: Text('Pakai saran restock ($initial)'),
              ),
            const SizedBox(height: 8),
            _sensorCard(),
            ValueListenableBuilder<String?>(
              valueListenable: _sensors.gyroError,
              builder: (context, gyroErr, _) => ValueListenableBuilder<String?>(
                valueListenable: _sensors.accelError,
                builder: (context, accErr, _) {
                  final msg = gyroErr ?? accErr;
                  if (msg == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '$msg Gunakan tombol di layar.',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.black,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text('Tambah $_qty unit'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorCard() {
    final cw = _inverted ? 'mengurangi' : 'menambah';
    final ccw = _inverted ? 'menambah' : 'mengurangi';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: _sensorOn,
              onChanged: _busy ? null : _setSensorOn,
              activeThumbColor: AppColors.yellow,
              title: const Text('Kontrol sensor'),
              subtitle: const Text(
                'Putar HP seperti setir untuk mengubah jumlah. Goyang dua '
                'kali untuk konfirmasi.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
            if (_sensorOn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Searah jarum jam $cw, berlawanan $ccw (per langkah '
                      '$_step). Putar cepat, lalu kembalikan perlahan.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _inverted = !_inverted),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Balik arah putar'),
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
