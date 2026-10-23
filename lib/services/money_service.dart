import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'currency_service.dart';

typedef RateFetcher = Future<RateSnapshot> Function();
typedef RateLoader = Future<RateSnapshot?> Function();

/// Mata uang tampilan aplikasi. Semua nilai uang disimpan dalam Rupiah;
/// kelas ini hanya mengubah cara menampilkannya.
class MoneyService extends ChangeNotifier {
  MoneyService({
    RateFetcher? fetcher,
    RateLoader? loader,
    String code = 'IDR',
    RateSnapshot? rates,
  })  : _fetcher = fetcher ?? CurrencyService.instance.fetchLatest,
        _loader = loader ?? CurrencyService.instance.loadCached,
        _code = code,
        _rates = rates;

  static final MoneyService instance = MoneyService();

  static const String _prefKey = 'display_currency';
  static const Duration staleAfter = Duration(hours: 12);

  final RateFetcher _fetcher;
  final RateLoader _loader;

  String _code;
  RateSnapshot? _rates;

  String get code => _code;
  RateSnapshot? get rates => _rates;

  /// True bila tampilan benar-benar dikonversi (bukan Rupiah).
  bool get isConverted => _code != 'IDR' && _rates != null;

  bool get isStale {
    final r = _rates;
    if (r == null) return true;
    return DateTime.now().toUtc().difference(r.fetchedAt) > staleAfter;
  }

  /// Memuat pilihan tersimpan dan kurs dari SQLite (tanpa jaringan).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && CurrencyService.currencies.contains(saved)) {
        _code = saved;
      }
    } catch (_) {}
    try {
      _rates = await _loader();
    } catch (_) {}
    notifyListeners();
  }

  /// Memperbarui kurs di latar belakang bila sudah lama. Gagal = diabaikan.
  Future<void> refreshIfStale() async {
    if (_code == 'IDR' || !isStale) return;
    try {
      await refreshRates();
    } catch (_) {}
  }

  /// Mengambil kurs terbaru. Melempar [CurrencyException] bila gagal.
  Future<void> refreshRates() async {
    _rates = await _fetcher();
    notifyListeners();
  }

  /// Mengganti mata uang tampilan. Untuk non-Rupiah, kurs terbaru
  /// dicoba diambil; bila gagal dan sudah ada kurs tersimpan, kurs lama
  /// dipakai. Bila gagal dan belum ada kurs sama sekali, melempar
  /// [CurrencyException] dan mata uang tidak berubah.
  Future<void> setCurrency(String code) async {
    if (!CurrencyService.currencies.contains(code)) return;

    if (code != 'IDR') {
      try {
        _rates = await _fetcher();
      } on CurrencyException {
        if (_rates == null) rethrow;
      }
    }

    _code = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
    notifyListeners();
  }

  /// Nilai dalam Rupiah -> teks pada mata uang tampilan.
  String format(int idr) {
    final r = _rates;
    if (_code == 'IDR' || r == null) {
      return CurrencyService.format('IDR', idr.toDouble());
    }
    try {
      return CurrencyService.format(
        _code,
        r.convert(idr.toDouble(), 'IDR', _code),
      );
    } on CurrencyException {
      return CurrencyService.format('IDR', idr.toDouble());
    }
  }
}