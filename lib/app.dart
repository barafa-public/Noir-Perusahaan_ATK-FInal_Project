import 'package:flutter/material.dart';

import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/navigation.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/main_shell.dart';
import 'services/auth_service.dart';

class NoirApp extends StatelessWidget {
  const NoirApp({super.key});

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
