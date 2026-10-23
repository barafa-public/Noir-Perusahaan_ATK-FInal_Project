import 'package:flutter/material.dart';

import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/navigation.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/main_shell.dart';
import 'services/auth_service.dart';
import 'services/money_service.dart';
import 'services/time_service.dart';

class NoirApp extends StatefulWidget {
  const NoirApp({super.key});

  @override
  State<NoirApp> createState() => _NoirAppState();
}

class _NoirAppState extends State<NoirApp> {
  @override
  void initState() {
    super.initState();
    MoneyService.instance.addListener(_rebuildAll);
    TimeService.instance.displayZone.addListener(_rebuildAll);
  }

  @override
  void dispose() {
    MoneyService.instance.removeListener(_rebuildAll);
    TimeService.instance.displayZone.removeListener(_rebuildAll);
    super.dispose();
  }

  /// Membangun ulang semua widget (state dan navigasi tetap), agar semua
  /// teks uang di layar yang sedang terbuka ikut berganti mata uang.
  void _rebuildAll() {
    if (!mounted) return;
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noir',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.dark,
      home: ListenableBuilder(
        listenable: AuthService.instance,
        builder: (context, _) {
          return switch (AuthService.instance.status) {
            AuthStatus.unknown => const _Splash(),
            AuthStatus.unauthenticated => const LoginScreen(),
            AuthStatus.authenticated => const MainShell(),
          };
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.yellow)),
    );
  }
}
