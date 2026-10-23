import '../../services/money_service.dart';
import '../../services/currency_service.dart';
import '../../services/time_service.dart';

class Formatters {
  Formatters._();

  /// Nilai dalam Rupiah (int) ditampilkan pada mata uang pilihan pengguna.
  /// 52000 -> "Rp 52.000" (IDR), "US$ 3,25" (USD), dst.
  /// Nama fungsi dipertahankan agar semua layar yang sudah ada otomatis ikut.
  static String rupiah(int value) => MoneyService.instance.format(value);

  /// Selalu Rupiah, tidak dikonversi. Untuk isian formulir harga.
  static String idr(int value) =>
      CurrencyService.format('IDR', value.toDouble());

  /// ISO-8601 (UTC) -> teks pada zona tampilan yang dipilih.
  static String dateTime(String iso) => TimeService.instance.formatIso(iso);
}