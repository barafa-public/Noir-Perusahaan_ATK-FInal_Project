class Validators {
  Validators._();

  static String? required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label wajib diisi' : null;
}
