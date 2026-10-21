import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/block_model.dart';
import '../../services/api_client.dart';
import '../../services/blockchain_service.dart';
import '../../services/time_service.dart';
import '../../widgets/error_view.dart';

class BlockchainScreen extends StatefulWidget {
  const BlockchainScreen({super.key});

  @override
  State<BlockchainScreen> createState() => _BlockchainScreenState();
}

class _BlockchainScreenState extends State<BlockchainScreen> {
  List<BlockModel> _blocks = const [];
  bool _loading = true;
  bool _verifying = false;
  String? _error;
  VerifyResult? _result;
  DateTime? _verifiedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blocks = await BlockchainService.instance.fetchAll();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _result = null; // data berubah, hasil verifikasi lama tidak berlaku
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      final out = await BlockchainService.instance.verifyOnline();
      if (!mounted) return;
      setState(() {
        _blocks = out.blocks;
        _result = out.result;
        _verifiedAt = DateTime.now();
        _verifying = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Verifikasi gagal: ${e.message}')));
    }
  }

  void _showDetail(BlockModel b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Blok #${b.index} · ${b.type}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _detail('Waktu dicatat', Formatters.dateTime(b.createdAt)),
                _detail('ID penjualan', b.refId ?? '-'),
                _detail('Payload', b.payload),
                _detail('prev_hash', b.prevHash, mono: true),
                _detail('hash', b.hash, mono: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontFamily: mono ? 'monospace' : null,
            fontSize: mono ? 12.5 : 14,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blockchain'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: (_loading || _verifying) ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _blocks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    }
    if (_error != null && _blocks.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: AppColors.yellow,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        itemCount: _blocks.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _header();
          // Terbaru di atas.
          final b = _blocks[_blocks.length - i];
          return _BlockTile(
            block: b,
            isBad: _result?.badIndex == b.index && _result?.ok == false,
            onTap: () => _showDetail(b),
          );
        },
      ),
    );
  }

  Widget _header() {
    final r = _result;
    final saleCount = _blocks.where((b) => !b.isGenesis).length;

    String verifiedLabel = '';
    final at = _verifiedAt;
    if (at != null) {
      final utc = at.toUtc();
      final z = TimeService.instance.displayZone.value;
      verifiedLabel =
          'Diperiksa ${TimeService.formatClock(TimeService.toZone(utc, z))} '
          '${TimeService.abbreviation(z, utc)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rantai blok penjualan',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_blocks.length} blok · $saleCount penjualan tercatat',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Penjualan baru tercatat setelah terkirim ke server.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: (_verifying || _blocks.isEmpty) ? null : _verify,
                    icon: _verifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.black,
                            ),
                          )
                        : const Icon(Icons.verified_user_rounded),
                    label: const Text('Verifikasi Integritas'),
                  ),
                ],
              ),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (r.ok ? AppColors.success : AppColors.error).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (r.ok ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: r.ok ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.ok ? 'Integritas terjaga' : 'Integritas terganggu',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: r.ok ? AppColors.success : AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(r.message),
                        if (verifiedLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            verifiedLabel,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  final BlockModel block;
  final bool isBad;
  final VoidCallback onTap;

  const _BlockTile({
    required this.block,
    required this.isBad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = block;
    final f = b.fields;
    final title = b.isGenesis
        ? 'Blok Genesis'
        : '${f['product'] ?? 'Penjualan'} × ${f['qty'] ?? '?'}';
    final subtitle = b.isGenesis
        ? 'Awal rantai'
        : '${Formatters.rupiah(int.tryParse(f['total'] ?? '') ?? 0)} · '
              '${Formatters.dateTime(b.createdAt)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBad ? AppColors.error : AppColors.border,
          width: isBad ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isBad ? AppColors.error : AppColors.yellow,
                foregroundColor: AppColors.black,
                child: Text(
                  '#${b.index}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'hash ${BlockModel.shortHash(b.hash)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
