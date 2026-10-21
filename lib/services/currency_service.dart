import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'db_helper.dart';

class CurrencyException implements Exception {
  final String message;
  const CurrencyException(this.message);

  @override
  String toString() => message;
}

/// Kurs terhadap USD: perUsd['IDR'] = 18043 berarti 1 USD = 18043 IDR.
class RateSnapshot {
  final Map<String, double> perUsd;
  final DateTime fetchedAt; // UTC

  const RateSnapshot({required this.perUsd, required this.fetchedAt});

  double convert(double amount, String from, String to) {
    final rf = perUsd[from];
    final rt = perUsd[to];
    if (rf == null || rt == null || rf == 0) {
      throw CurrencyException('Kurs $from ke $to belum tersedia.');
    }
    return amount / rf * rt;
  }
}

class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  static const List<String> currencies = ['IDR', 'USD', 'EUR'];
  static const String _base = 'USD';

  static final Uri _url = Uri.parse(
    'https://api.frankfurter.dev/v1/latest?base=USD&symbols=IDR,EUR',
  );

  /// Kurs tersimpan terakhir (SQLite), atau null jika belum pernah diambil.
  Future<RateSnapshot?> loadCached() async {
    final rows = await DbHelper.instance.getExchangeRates(_base);
    if (rows.isEmpty) return null;

    final perUsd = <String, double>{_base: 1.0};
    String? fetched;
    for (final r in rows) {
      perUsd[r['target'] as String] = (r['rate'] as num).toDouble();
      fetched = r['fetched_at'] as String;
    }
    final at = DateTime.tryParse(fetched ?? '');
    if (at == null || !currencies.every(perUsd.containsKey)) return null;
    return RateSnapshot(perUsd: perUsd, fetchedAt: at.toUtc());
  }

  /// Mengambil kurs terbaru dari API lalu menyimpannya ke SQLite.
  /// Melempar [CurrencyException] bila gagal.
  Future<RateSnapshot> fetchLatest() async {
    final http.Response res;
    try {
      res = await http.get(_url, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const CurrencyException('Server kurs tidak merespons. Coba lagi.');
    } catch (_) {
      throw const CurrencyException('Tidak dapat terhubung ke server kurs.');
    }

    if (res.statusCode != 200) {
      throw CurrencyException(
        'Server kurs mengembalikan kesalahan (${res.statusCode}).',
      );
    }

    final perUsd = <String, double>{_base: 1.0};
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = json['rates'] as Map<String, dynamic>;
      for (final c in currencies) {
        if (c == _base) continue;
        perUsd[c] = (rates[c] as num).toDouble();
      }
    } catch (_) {
      throw const CurrencyException('Format data kurs tidak dikenali.');
    }

    final now = DateTime.now().toUtc();
    await DbHelper.instance.saveExchangeRates(
      _base,
      {
        for (final e in perUsd.entries)
          if (e.key != _base) e.key: e.value,
      },
      now.toIso8601String(),
    );
    return RateSnapshot(perUsd: perUsd, fetchedAt: now);
  }

  // ------------------------------------------------------------------
  // Format dan parsing (statis, mudah diuji)
  // ------------------------------------------------------------------

  /// 1804300, 'IDR' -> "Rp 1.804.300"; 1234.5, 'USD' -> "US$ 1.234,50".
  static String format(String code, double value) {
    final decimals = code == 'IDR' ? 0 : 2;
    final fixed = value.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final grouped = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final body = decimals == 0 ? grouped : '$grouped,${parts[1]}';
    final symbol = switch (code) {
      'IDR' => 'Rp',
      'USD' => 'US\$',
      'EUR' => '€',
      _ => code,
    };
    return '${value < 0 ? '-' : ''}$symbol $body';
  }

  /// "100000", "12,5" atau "12.5" -> angka. Tanpa pemisah ribuan.
  static double? parseAmount(String input) {
    final cleaned = input.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
