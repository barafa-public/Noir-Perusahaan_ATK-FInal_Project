import '../../services/time_service.dart';

class Formatters {
  Formatters._();

  /// 52000 -> "Rp 52.000"
  static String rupiah(int value) {
    final digits = value.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '${value < 0 ? '-' : ''}Rp $grouped';
  }

  /// ISO-8601 (UTC) -> "20 Okt 2026, 14.05 WIB" pada zona tampilan
  /// yang dipilih di layar Konversi Waktu (bawaan WIB).
  static String dateTime(String iso) => TimeService.instance.formatIso(iso);
}
