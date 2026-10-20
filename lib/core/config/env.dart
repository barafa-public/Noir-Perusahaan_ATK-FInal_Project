import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static String get backendUrl {
    final v = (dotenv.env['BACKEND_URL'] ?? '').trim();
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  static String get publishableKey =>
      (dotenv.env['BACKEND_PUBLISHABLE_KEY'] ?? '').trim();

  static bool get isConfigured =>
      backendUrl.isNotEmpty && publishableKey.isNotEmpty;
}
