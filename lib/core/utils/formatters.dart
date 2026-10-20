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
}
