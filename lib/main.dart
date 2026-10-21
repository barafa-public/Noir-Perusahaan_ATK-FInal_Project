import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:noir_final_project/services/time_service.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/db_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await DbHelper.instance.database;
  await TimeService.instance.load();
  await AuthService.instance.restoreSession();
  runApp(const NoirApp());
}
