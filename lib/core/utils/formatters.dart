class Formatters {
  Formatters._();

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

  /// 52000 -> "Rp 52.000"
  static String rupiah(int value) {
    final digits = value.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '${value < 0 ? '-' : ''}Rp $grouped';
  }

  /// ISO-8601 (UTC) -> "20 Okt 2026, 14.05" pada zona waktu perangkat.
  /// Konversi WIB/WITA/WIT/London ditambahkan di Sprint 4 (PBI-11).
  static String dateTime(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, '
        '${two(d.hour)}.${two(d.minute)}';
  }
}
