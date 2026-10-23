import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/currency_service.dart';
import '../../services/money_service.dart';

class CurrencySettingsScreen extends StatefulWidget {
  const CurrencySettingsScreen({super.key});

  @override
  State<CurrencySettingsScreen> createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  static const _names = {
    'IDR': 'Rupiah Indonesia',
    'USD': 'Dolar Amerika Serikat',
    'EUR': 'Euro',
  };
  static const _symbols = {'IDR': 'Rp', 'USD': 'US\$', 'EUR': '€'};

  final MoneyService _money = MoneyService.instance;
  String? _busyCode;
  bool _refreshing = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _select(String code) async {
    if (code == _money.code || _busyCode != null) return;
    setState(() => _busyCode = code);
    try {
      await _money.setCurrency(code);
    } on CurrencyException catch (e) {
      _snack('${e.message} Mata uang tidak diubah.');
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _money.refreshRates();
      _snack('Kurs diperbarui.');
    } on CurrencyException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mata Uang')),
      body: ListenableBuilder(
        listenable: _money,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Pilih mata uang untuk menampilkan harga di seluruh aplikasi: '
              'produk, catatan penjualan, dan riwayat.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            for (final code in CurrencyService.currencies) _option(code),
            const SizedBox(height: 8),
            if (_money.isConverted) _example(),
            const SizedBox(height: 8),
            _rateCard(),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Perbarui kurs'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Data tetap tersimpan dalam Rupiah. Konversi hanya mengubah '
              'tampilan dan memakai kurs terbaru, termasuk untuk transaksi lama. '
              'Isian harga produk tetap dalam Rupiah.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(String code) {
    final selected = _money.code == code;
    final busy = _busyCode == code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? AppColors.yellow.withValues(alpha: 0.12)
            : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.yellow : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: SizedBox(
            width: 44,
            child: Text(
              _symbols[code] ?? code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.yellow,
              ),
            ),
          ),
          title: Text(
            _names[code] ?? code,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            code,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : selected
              ? const Icon(Icons.check_circle_rounded, color: AppColors.yellow)
              : null,
          onTap: () => _select(code),
        ),
      ),
    );
  }

  Widget _example() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Formatters.idr(52000)),
            const Icon(Icons.arrow_forward_rounded, size: 18),
            Text(
              _money.format(52000),
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

  String _idrPer(RateSnapshot r, String from) {
    final idr = CurrencyService.format('IDR', r.convert(1, from, 'IDR'));
    return '1 $from = $idr';
  }

  Widget _rateCard() {
    final r = _money.rates;
    if (r == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Belum ada kurs tersimpan. Sambungkan internet, lalu pilih '
            'mata uang atau tekan Perbarui kurs.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final updated = Formatters.dateTime(r.fetchedAt.toIso8601String());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _idrPer(r, 'USD'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _idrPer(r, 'EUR'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Diperbarui $updated',
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
}
