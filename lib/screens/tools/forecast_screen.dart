import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/forecast_service.dart';
import '../../services/sync_service.dart';
import '../../services/time_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  ForecastConfig _config = const ForecastConfig();
  bool _demo = false;
  ForecastReport? _report;
  bool _loading = true;
  String? _error;
  Urgency? _filter;

  @override
  void initState() {
    super.initState();
    SyncService.instance.salesChanged.addListener(_load);
    TimeService.instance.displayZone.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.salesChanged.removeListener(_load);
    TimeService.instance.displayZone.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ForecastService.instance.loadReport(
        config: _config,
        demo: _demo,
      );
      if (!mounted) return;
      setState(() {
        _report = r;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal menghitung prediksi.';
        _loading = false;
      });
    }
  }

  Future<void> _openParams() async {
    var lead = _config.leadTimeDays;
    var cover = _config.coverDays;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Parameter rekomendasi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Text('Waktu tunggu barang datang: $lead hari'),
                Slider(
                  value: lead.toDouble(),
                  min: 1,
                  max: 14,
                  divisions: 13,
                  label: '$lead',
                  onChanged: (v) => setSheet(() => lead = v.round()),
                ),
                Text('Stok target cukup untuk: $cover hari'),
                Slider(
                  value: cover.toDouble(),
                  min: 7,
                  max: 30,
                  divisions: 23,
                  label: '$cover',
                  onChanged: (v) => setSheet(() => cover = v.round()),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Terapkan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _config = _config.copyWith(leadTimeDays: lead, coverDays: cover);
        _loading = true;
      });
      _load();
    }
  }

  void _toggleDemo(bool v) {
    setState(() {
      _demo = v;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prediksi Stok'),
        actions: [
          IconButton(
            tooltip: 'Parameter',
            onPressed: _openParams,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    }
    final r = _report;
    if (_error != null || r == null) {
      return ErrorView(
        message: _error ?? 'Prediksi tidak tersedia.',
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (r.items.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Belum ada produk',
        message: 'Tambahkan produk dan catat penjualan untuk melihat prediksi.',
      );
    }

    final shown = _filter == null
        ? r.items
        : r.items.where((f) => f.urgency == _filter).toList();

    return RefreshIndicator(
      color: AppColors.yellow,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        await SyncService.instance.syncAll();
        await _load();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _summary(r),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              value: _demo,
              onChanged: _toggleDemo,
              activeThumbColor: AppColors.yellow,
              title: const Text('Pakai data contoh'),
              subtitle: const Text(
                'Simulasi riwayat 35 hari. Tidak disimpan dan tidak mengubah '
                'data toko.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
          ),
          if (r.historyDays < 21) ...[
            const SizedBox(height: 12),
            _historyNote(r.historyDays),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip('Semua', null),
              _chip('Mendesak', Urgency.critical),
              _chip('Segera', Urgency.soon),
              _chip('Aman', Urgency.ok),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Tidak ada produk pada kategori ini.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          for (final f in shown)
            _ForecastCard(forecast: f, onTap: () => _showDetail(r, f)),
        ],
      ),
    );
  }

  Widget _chip(String label, Urgency? value) => ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      );

  Widget _summary(ForecastReport r) {
    Widget stat(String label, int n, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                stat('Mendesak', r.countOf(Urgency.critical), AppColors.error),
                stat('Segera', r.countOf(Urgency.soon), AppColors.yellow),
                stat('Aman', r.countOf(Urgency.ok), AppColors.success),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Model regresi linear dengan faktor hari dalam minggu, dilatih '
              'dari ${r.historyDays} hari riwayat penjualan. Waktu tunggu '
              '${r.config.leadTimeDays} hari, cakupan stok '
              '${r.config.coverDays} hari.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyNote(int days) {
    final text = days < 7
        ? 'Riwayat penjualan baru $days hari. Prediksi aktif setelah 7 hari; '
            'sementara saran restock memakai stok minimum.'
        : 'Riwayat penjualan $days hari. Prediksi sudah berjalan, tetapi baru '
            'bisa diuji akurasinya setelah 21 hari.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.yellow)),
    );
  }

  // ------------------------------------------------------------------
  // Rincian satu produk
  // ------------------------------------------------------------------

  void _showDetail(ForecastReport r, ProductForecast f) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: const TextStyle(color: AppColors.textSecondary)),
              Flexible(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );

    final trend = f.trendPct;
    final lead = r.config.leadTimeDays;
    final cover = r.config.coverDays;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.product.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              kv('Stok saat ini', '${f.product.stock}'),
              kv('Stok minimum', '${f.product.minStock}'),
              kv('Rata-rata terjual per hari', _num(f.recentAvg)),
              if (f.basedOnForecast) ...[
                kv('Prediksi per hari (7 hari ke depan)',
                    _num(f.predictedDaily)),
                kv(
                  'Tren',
                  trend == null
                      ? 'belum bisa dihitung'
                      : '${trend >= 0 ? '+' : ''}${(trend * 100).round()}% '
                          'dibanding minggu lalu',
                ),
                kv(
                  'Galat model (WAPE)',
                  f.wape == null
                      ? 'belum bisa diukur'
                      : '${(f.wape! * 100).round()}%',
                ),
              ],
              kv('Tingkat keyakinan', _confidenceLabel(f.confidence)),
              const Divider(height: 24),
              const Text(
                'Cara menghitung saran restock',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.yellow,
                ),
              ),
              const SizedBox(height: 8),
              if (f.basedOnForecast) ...[
                Text(
                  'Permintaan ${lead + cover} hari ke depan '
                  '(waktu tunggu $lead + cakupan $cover): '
                  '${_num(f.horizonDemand)}\n'
                  'Stok pengaman: ${_num(f.safetyStock)}\n'
                  'Target stok: ${_num(f.targetStock)}\n'
                  'Saran restock = target − stok saat ini = '
                  '${f.restockQty} unit',
                  style: const TextStyle(height: 1.5),
                ),
              ] else
                Text(
                  'Data penjualan belum cukup, jadi target memakai 2× stok '
                  'minimum (${f.product.minStock * 2}). Saran restock = target '
                  '− stok saat ini = ${f.restockQty} unit.',
                  style: const TextStyle(height: 1.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Kartu produk
// =====================================================================

String _num(double v) =>
    v >= 10 ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

String _confidenceLabel(Confidence c) => switch (c) {
      Confidence.insufficient => 'Data belum cukup',
      Confidence.low => 'Rendah',
      Confidence.medium => 'Sedang',
      Confidence.high => 'Tinggi',
    };

class _ForecastCard extends StatelessWidget {
  final ProductForecast forecast;
  final VoidCallback onTap;

  const _ForecastCard({required this.forecast, required this.onTap});

  String _daysLeftText(ProductForecast f) {
    if (f.product.stock <= 0) return 'Habis';
    if (!f.basedOnForecast) return '-';
    final d = f.daysLeft;
    if (d == null) return '> 60 hari';
    if (d < 1) return '< 1 hari';
    return '≈ ${d.round()} hari';
  }

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final (Color color, String label) = switch (f.urgency) {
      Urgency.critical => (AppColors.error, 'Mendesak'),
      Urgency.soon => (AppColors.yellow, 'Segera'),
      Urgency.ok => (AppColors.success, 'Aman'),
    };
    final trend = f.trendPct;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${f.product.category} · stok ${f.product.stock}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _metric('Habis dalam', _daysLeftText(f)),
                  _metric(
                    'Prediksi 7 hari',
                    f.basedOnForecast ? '${f.weekTotal.round()} unit' : '-',
                  ),
                  _metric(
                    'Saran restock',
                    f.restockQty > 0 ? '+${f.restockQty} unit' : '-',
                    highlight: f.restockQty > 0,
                  ),
                ],
              ),
              if (f.history.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      history: f.history,
                      forecast: f.next7,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Keyakinan: ${_confidenceLabel(f.confidence)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (trend != null)
                    Text(
                      trend >= 0
                          ? '▲ naik ${(trend * 100).round()}%'
                          : '▼ turun ${(-trend * 100).round()}%',
                      style: TextStyle(
                        color: trend >= 0 ? AppColors.success : AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  if (f.slow)
                    const Text(
                      'Perputaran lambat',
                      style: TextStyle(
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

  Widget _metric(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.yellow : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Batang abu-abu = terjual per hari (riwayat), kuning = prediksi 7 hari.
class _SparklinePainter extends CustomPainter {
  final List<double> history;
  final List<double> forecast;

  _SparklinePainter({required this.history, required this.forecast});

  @override
  void paint(Canvas canvas, Size size) {
    final total = history.length + forecast.length;
    if (total == 0) return;

    var maxV = 1.0;
    for (final v in [...history, ...forecast]) {
      if (v > maxV) maxV = v;
    }

    const gap = 2.0;
    final barW = (size.width - gap * (total - 1)) / total;
    if (barW <= 0) return;

    final histPaint = Paint()..color = AppColors.border;
    final fcPaint = Paint()..color = AppColors.yellow;

    for (var i = 0; i < total; i++) {
      final isForecast = i >= history.length;
      final v = isForecast ? forecast[i - history.length] : history[i];
      final h = (v / maxV * size.height).clamp(1.5, size.height);
      final left = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barW, h),
          const Radius.circular(1.5),
        ),
        isForecast ? fcPaint : histPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.history != history || old.forecast != forecast;
}
