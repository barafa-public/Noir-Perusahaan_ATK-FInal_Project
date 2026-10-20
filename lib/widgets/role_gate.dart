import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Menampilkan [child] hanya jika role pengguna yang login ada di [allowed].
/// Dipakai untuk menu/tombol per role. Pengamanan sebenarnya tetap di server.
class RoleGate extends StatelessWidget {
  final List<String> allowed;
  final Widget child;
  final Widget? fallback;

  const RoleGate({
    super.key,
    required this.allowed,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    if (user != null && allowed.contains(user.role)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
