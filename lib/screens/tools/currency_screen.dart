import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../services/currency_service.dart';
import '../../services/time_service.dart';
import '../../widgets/error_view.dart';

class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  final _amount = TextEditingController(text: '100000');

  String _from = 'IDR';
  String _to = 'USD';

  RateSnapshot? _rates;
  bool _loading = true;
  bool _offline = false;
  String? _error; // hanya jika belum ada kurs sama sekali

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Tampilkan kurs tersimpan dulu agar langsung terlihat, lalu perbarui.
    final cached = await CurrencyService.instance.loadCached();
    if (!mounted) return;
    if (cached != null) setState(() => _rates = cached);
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await CurrencyService.instance.fetchLatest();
      if (!mounted) return;
      setState(() {
        _rates = fresh;
        _offline = false;
        _loading = false;
      });
    } on CurrencyException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = _rates != null;
        _error = _rates == null ? e.message : null;
      });
    }
  }

  void _swap() => setState(() {
        final t = _from;
        _from = _to;
        _to = t;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konversi Mata Uang'),
        actions: [
          IconButton(
            tooltip: 'Perbarui kurs',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final rates = _rates;
    if (rates == null) {
      if (_loading) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.yellow),
        );
      }
      return ErrorView(
        message: _error ?? 'Kurs belum tersedia.',
        onRetry: _refresh,
      );
    }

    final amount = CurrencyService.parseAmount(_amount.text);
    String result = '-';
    String rateLine = '';
    if (amount != null) {
      result = CurrencyService.format(_to, rates.convert(amount, _from, _to));
    }
    if (_from != _to) {
      // Tampilkan kurs sebagai "1 mata uang kuat = X mata uang lemah".
      final forward = rates.convert(1, _from, _to);
      final strong = forward >= 1 ? _from : _to;
      final weak = forward >= 1 ? _to : _from;
      rateLine =
          '1 $strong = ${CurrencyService.format(weak, rates.convert(1, strong, weak))}';
    }

    final updated = TimeService.instance.formatIso(
      rates.fetchedAt.toIso8601String(),
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_loading) ...[
          const LinearProgressIndicator(color: AppColors.yellow),
          const SizedBox(height: 12),
        ],
        if (_offline)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.yellow.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'Tidak bisa memperbarui kurs. Memakai kurs tersimpan terakhir.',
              style: TextStyle(color: AppColors.yellow),
            ),
          ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          ],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Jumlah (desimal pakai titik atau koma)',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Dari', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _CurrencyChips(
          selected: _from,
          onSelected: (c) => setState(() => _from = c),
        ),
        const SizedBox(height: 8),
        Center(
          child: IconButton(
            tooltip: 'Tukar',
            onPressed: _swap,
            icon: const Icon(Icons.swap_vert_rounded, color: AppColors.yellow),
          ),
        ),
        const Text('Ke', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _CurrencyChips(
          selected: _to,
          onSelected: (c) => setState(() => _to = c),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hasil',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  result,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.yellow,
                  ),
                ),
                if (rateLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    rateLine,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Kurs diperbarui: $updated\nSumber: Frankfurter (data Bank Sentral Eropa)',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _CurrencyChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _CurrencyChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: CurrencyService.currencies
          .map(
            (c) => ChoiceChip(
              label: Text(c),
              selected: selected == c,
              onSelected: (_) => onSelected(c),
            ),
          )
          .toList(),
    );
  }
}
