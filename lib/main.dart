import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import 'core/theme/app_theme.dart';
import 'services/db_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final db = await DbHelper.instance.database;
  if (kDebugMode) {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    debugPrint('SQLite tables: ${tables.map((t) => t['name']).toList()}');
  }

  runApp(const NoirApp());
}

class NoirApp extends StatelessWidget {
  const NoirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noir',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Scaffold(body: Center(child: Text('Noir'))),
    );
  }
}