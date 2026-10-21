import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/alert_service.dart';
import '../../services/auth_service.dart';
import '../../services/profile_photo_service.dart';
import '../../services/sync_service.dart';
import '../feedback/feedback_screen.dart';
import '../home/internal_home_screen.dart';
import '../products/product_list_screen.dart';
import '../profile/profile_screen.dart';

class _NavTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Empat tab sesuai Ketentuan Proyek.
  static const List<_NavTab> _tabs = [
    _NavTab(
      label: 'Beranda',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      page: InternalHomeScreen(),
    ),
    _NavTab(
      label: 'Produk',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      page: ProductListScreen(),
    ),
    _NavTab(
      label: 'Saran & Kesan',
      icon: Icons.rate_review_outlined,
      selectedIcon: Icons.rate_review_rounded,
      page: FeedbackScreen(),
    ),
    _NavTab(
      label: 'Profil',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      page: ProfileScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.user;
    if (user != null) {
      ProfilePhotoService.instance.load(user.id);
    }
    SyncService.instance.startAutoSync();
    unawaited(AlertService.instance.start());
    unawaited(
      SyncService.instance.syncAll().then((r) => debugPrint(r.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((t) => t.page).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
