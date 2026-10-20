import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/db_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await DbHelper.instance.database;
  await AuthService.instance.restoreSession();
  runApp(const NoirApp());
}
