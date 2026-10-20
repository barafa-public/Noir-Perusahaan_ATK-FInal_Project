import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/profile_photo_service.dart';
import '../../widgets/empty_state.dart';
import '../feedback/feedback_screen.dart';
import '../home/customer_home_screen.dart';
import '../home/internal_home_screen.dart';
import '../profile/profile_screen.dart';

import 'dart:async';

import '../../services/sync_service.dart';
import '../products/product_list_screen.dart';

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

/// Halaman kosong sementara untuk fitur yang dibangun di sprint berikutnya.
class _ComingSoon extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;

  const _ComingSoon({
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(icon: icon, title: 'Segera hadir', message: message),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final List<_NavTab> _tabs;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.user;
    _tabs = _buildTabs(user?.isInternal ?? false);
    if (user != null) {
      ProfilePhotoService.instance.load(user.id);
    }
    unawaited(
      SyncService.instance.syncAll().then((r) => debugPrint(r.toString())),
    );
  }

  /// Empat tab wajib (Beranda, Produk, Saran & Kesan, Profil) ditambah
  /// satu tab khusus role: Pesanan (Customer) atau Transaksi (User internal).
  List<_NavTab> _buildTabs(bool internal) {
    return [
      _NavTab(
        label: 'Beranda',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        page:
            internal ? const InternalHomeScreen() : const CustomerHomeScreen(),
      ),
      _NavTab(
        label: 'Produk',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        page: const ProductListScreen(),
      ),
      if (internal)
        const _NavTab(
          label: 'Transaksi',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          page: _ComingSoon(
            title: 'Transaksi',
            icon: Icons.receipt_long_outlined,
            message: 'Pesanan masuk dan penjualan dikerjakan di Sprint 3.',
          ),
        )
      else
        const _NavTab(
          label: 'Pesanan',
          icon: Icons.shopping_bag_outlined,
          selectedIcon: Icons.shopping_bag_rounded,
          page: _ComingSoon(
            title: 'Pesanan Saya',
            icon: Icons.shopping_bag_outlined,
            message: 'Keranjang dan pesanan dikerjakan di Sprint 2.',
          ),
        ),
      const _NavTab(
        label: 'Saran',
        icon: Icons.rate_review_outlined,
        selectedIcon: Icons.rate_review_rounded,
        page: FeedbackScreen(),
      ),
      const _NavTab(
        label: 'Profil',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        page: ProfileScreen(),
      ),
    ];
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
