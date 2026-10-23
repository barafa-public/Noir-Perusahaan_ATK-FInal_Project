import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/db_helper.dart';
import 'services/money_service.dart';
import 'services/time_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await DbHelper.instance.database;
  await TimeService.instance.load();
  await MoneyService.instance.load();
  unawaited(MoneyService.instance.refreshIfStale());
  await AuthService.instance.restoreSession();
  runApp(const NoirApp());
}
