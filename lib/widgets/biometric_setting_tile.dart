import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';

class BiometricSettingTile extends StatefulWidget {
  const BiometricSettingTile({super.key});

  @override
  State<BiometricSettingTile> createState() => _BiometricSettingTileState();
}

class _BiometricSettingTileState extends State<BiometricSettingTile> {
  bool _loaded = false;
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricService.instance.isAvailable();
    final enabledUser = await BiometricService.instance.enabledUsername;
    final me = AuthService.instance.user?.username;
    if (!mounted) return;
    setState(() {
      _available = available;
      // Aktif hanya jika kredensial tersimpan milik akun yang sedang login.
      _enabled = enabledUser != null && enabledUser == me;
      _loaded = true;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        await _enable();
      } else {
        await BiometricService.instance.disable();
        _snack('Login biometrik dinonaktifkan');
      }
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    final password = await _askPassword();
    if (password == null || password.isEmpty) return;

    final bio = await BiometricService.instance.authenticate(
      'Konfirmasi untuk mengaktifkan login biometrik',
    );
    if (!bio.success) {
      if (bio.message != null) _snack(bio.message!);
      return;
    }

    await AuthService.instance.enableBiometric(password);
    _snack('Login biometrik diaktifkan');
  }

  Future<String?> _askPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Konfirmasi password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan password akun Anda untuk mengaktifkan login biometrik.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Password'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    if (!_loaded) {
      subtitle = 'Memeriksa perangkat...';
    } else if (!_available) {
      subtitle = 'Tidak tersedia: perangkat tidak mendukung atau belum ada sidik jari/wajah terdaftar.';
    } else {
      subtitle = 'Masuk lebih cepat dengan sidik jari atau wajah.';
    }

    return Card(
      child: SwitchListTile(
        value: _enabled,
        onChanged: (!_loaded || !_available || _busy) ? null : _toggle,
        secondary: const Icon(
          Icons.fingerprint_rounded,
          color: AppColors.yellow,
        ),
        title: const Text('Login biometrik'),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
