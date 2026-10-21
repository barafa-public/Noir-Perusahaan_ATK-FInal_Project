import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppZone { wib, wita, wit, london }

/// Konversi zona waktu tanpa paket tambahan.
/// "Waktu dinding" (wall time) direpresentasikan sebagai DateTime berflag UTC
/// yang field-nya sudah digeser sesuai zona; jangan dibaca sebagai UTC asli.
class TimeService {
  TimeService._();
  static final TimeService instance = TimeService._();

  static const _prefKey = 'display_zone';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  static const _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// Zona yang dipakai untuk menampilkan waktu di seluruh aplikasi
  /// (mis. Riwayat Penjualan). Bawaan: WIB.
  final ValueNotifier<AppZone> displayZone = ValueNotifier(AppZone.wib);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefKey);
      for (final z in AppZone.values) {
        if (z.name == id) displayZone.value = z;
      }
    } catch (_) {
      // Pakai bawaan.
    }
  }

  Future<void> setDisplayZone(AppZone zone) async {
    displayZone.value = zone;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, zone.name);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Aturan zona
  // ------------------------------------------------------------------

  static String zoneName(AppZone z) => switch (z) {
        AppZone.wib => 'WIB (Jakarta)',
        AppZone.wita => 'WITA (Makassar)',
        AppZone.wit => 'WIT (Jayapura)',
        AppZone.london => 'London',
      };

  /// Hari Minggu terakhir pada [month] pukul [hourUtc] UTC.
  static DateTime _lastSundayUtc(int year, int month, int hourUtc) {
    final lastDay = DateTime.utc(year, month + 1, 0);
    final back = lastDay.weekday % 7; // Minggu = 7 -> 0
    final d = lastDay.subtract(Duration(days: back));
    return DateTime.utc(d.year, d.month, d.day, hourUtc);
  }

  /// London memakai BST (UTC+1) dari Minggu terakhir Maret 01:00 UTC sampai
  /// Minggu terakhir Oktober 01:00 UTC.
  static bool _isLondonSummer(DateTime utc) {
    final u = utc.toUtc();
    final start = _lastSundayUtc(u.year, 3, 1);
    final end = _lastSundayUtc(u.year, 10, 1);
    return !u.isBefore(start) && u.isBefore(end);
  }

  /// Selisih menit dari UTC pada saat [utc].
  static int offsetMinutes(AppZone zone, DateTime utc) => switch (zone) {
        AppZone.wib => 7 * 60,
        AppZone.wita => 8 * 60,
        AppZone.wit => 9 * 60,
        AppZone.london => _isLondonSummer(utc) ? 60 : 0,
      };

  /// Singkatan zona pada saat [utc]: WIB, WITA, WIT, GMT atau BST.
  static String abbreviation(AppZone zone, DateTime utc) => switch (zone) {
        AppZone.wib => 'WIB',
        AppZone.wita => 'WITA',
        AppZone.wit => 'WIT',
        AppZone.london => _isLondonSummer(utc) ? 'BST' : 'GMT',
      };

  // ------------------------------------------------------------------
  // Konversi
  // ------------------------------------------------------------------

  /// UTC -> waktu dinding di [zone].
  static DateTime toZone(DateTime utc, AppZone zone) {
    final u = utc.toUtc();
    return u.add(Duration(minutes: offsetMinutes(zone, u)));
  }

  /// Waktu dinding di [zone] -> UTC. Untuk London, waktu yang ganda saat
  /// jam mundur diperlakukan sebagai BST (pertama).
  static DateTime toUtc(DateTime wall, AppZone zone) {
    final w = DateTime.utc(
        wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second);
    if (zone != AppZone.london) {
      return w.subtract(Duration(minutes: offsetMinutes(zone, w)));
    }
    final asBst = w.subtract(const Duration(minutes: 60));
    return _isLondonSummer(asBst) ? asBst : w;
  }

    /// Awal hari ini (pukul 00.00) di [zone], dinyatakan dalam UTC.
  static DateTime startOfDayUtc(AppZone zone, DateTime nowUtc) {
    final wall = toZone(nowUtc, zone);
    return toUtc(DateTime.utc(wall.year, wall.month, wall.day), zone);
  }

  // ------------------------------------------------------------------
  // Format
  // ------------------------------------------------------------------

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "21 Okt 2026, 21.05"
  static String formatDateTime(DateTime wall) =>
      '${wall.day} ${_months[wall.month - 1]} ${wall.year}, '
      '${_two(wall.hour)}.${_two(wall.minute)}';

  /// "21.05.33"
  static String formatClock(DateTime wall) =>
      '${_two(wall.hour)}.${_two(wall.minute)}.${_two(wall.second)}';

  /// "Rabu, 21 Okt 2026"
  static String formatDate(DateTime wall) =>
      '${_days[wall.weekday - 1]}, ${wall.day} ${_months[wall.month - 1]} ${wall.year}';

  /// ISO-8601 -> "21 Okt 2026, 21.05 WIB" pada zona tampilan (atau [zone]).
  String formatIso(String iso, {AppZone? zone}) {
    final utc = DateTime.tryParse(iso)?.toUtc();
    if (utc == null) return '-';
    final z = zone ?? displayZone.value;
    return '${formatDateTime(toZone(utc, z))} ${abbreviation(z, utc)}';
  }
}
