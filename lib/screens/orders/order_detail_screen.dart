import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order_model.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/db_helper.dart';
import '../../services/order_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/order_status_chip.dart';

/// Detail pesanan. Customer: hanya melihat. User internal: melihat pemesan
/// dan stok, serta dapat Proses / Selesai / Batalkan sesuai status.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderModel? _order;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, int> _stock = const {}; // product_id -> stok (hanya internal)

  bool get _isInternal => AuthService.instance.user?.isInternal ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await OrderService.instance.fetchOne(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _error = null;
        _loading = false;
      });
      if (_isInternal) _loadStock(o);
    } on ApiException catch (e) {
      if (!mounted) return;
      final hadData = _order != null;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (hadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat ulang: ${e.message}')),
        );
      }
    }
  }

  /// Menyegarkan cache produk lalu membaca stok tiap item, agar internal
  /// tahu apakah pesanan bisa diproses. Server tetap yang memutuskan.
  Future<void> _loadStock(OrderModel o) async {
    try {
      await SyncService.instance.syncProducts();
    } on ApiException {
      // offline: pakai cache apa adanya
    }
    final m = <String, int>{};
    for (final it in o.items) {
      final p = await DbHelper.instance.getProduct(it.productId);
      if (p != null) m[it.productId] = p.stock;
    }
    if (mounted) setState(() => _stock = m);
  }

  // ------------------------------------------------------------------
  // Aksi internal
  // ------------------------------------------------------------------

  Future<void> _run(
    Future<OrderModel> Function() action,
    String successMessage,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _order = updated);
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      _loadStock(updated);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // Status atau stok berubah di sisi server: ambil data terbaru.
      if (e.code == 'INVALID_STATUS' || e.code == 'INSUFFICIENT_STOCK') {
        if (mounted) _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String okLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 44),
              foregroundColor: AppColors.yellow,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onProcess(OrderModel o) async {
    final ok = await _confirm(
      'Proses pesanan?',
      'Stok produk akan dikurangi sesuai isi pesanan. '
          'Proses ditolak jika ada produk yang stoknya kurang.',
      'Proses',
    );
    if (!ok || !mounted) return;
    await _run(
      () => OrderService.instance.process(o.id),
      'Pesanan diproses. Stok dikurangi.',
    );
  }

  Future<void> _onComplete(OrderModel o) async {
    final ok = await _confirm(
      'Tandai selesai?',
      'Setelah selesai, pesanan tidak dapat dibatalkan lagi.',
      'Selesai',
    );
    if (!ok || !mounted) return;
    await _run(() => OrderService.instance.complete(o.id), 'Pesanan selesai.');
  }

  Future<void> _onCancel(OrderModel o) async {
    final returnsStock = o.status == OrderStatus.processing;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(returnsStock: returnsStock),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => OrderService.instance.cancel(o.id, reason),
      returnsStock
          ? 'Pesanan dibatalkan. Stok dikembalikan.'
          : 'Pesanan dibatalkan.',
    );
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  static String _hint(String status) => switch (status) {
    OrderStatus.ordered => 'Menunggu diproses oleh toko.',
    OrderStatus.processing => 'Pesanan sedang disiapkan toko.',
    OrderStatus.done => 'Pesanan telah selesai.',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final o = _order;

    Widget body;
    if (_loading) {
      body = const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    } else if (o == null) {
      body = ErrorView(
        message: _error ?? 'Pesanan tidak ditemukan.',
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    } else {
      body = _buildContent(o);
    }

    final showActions =
        _isInternal &&
        o != null &&
        (o.status == OrderStatus.ordered || o.status == OrderStatus.processing);

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Pesanan')),
      body: body,
      bottomNavigationBar: showActions ? _buildActionBar(o) : null,
    );
  }

  Widget _buildActionBar(OrderModel o) {
    final isOrdered = o.status == OrderStatus.ordered;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _onCancel(o),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  child: const Text('Batalkan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => isOrdered ? _onProcess(o) : _onComplete(o),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.black,
                          ),
                        )
                      : Text(isOrdered ? 'Proses' : 'Selesai'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(OrderModel o) {
    final customer = (o.customerName ?? '').trim();
    final processor = (o.processedByName ?? '').trim();
    final username = (o.customerUsername ?? '').trim();

    return RefreshIndicator(
      color: AppColors.yellow,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.orderNo,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(o.createdAt),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              OrderStatusChip(o.status),
            ],
          ),
          const SizedBox(height: 20),
          if (o.status == OrderStatus.cancelled)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                (o.cancelReason ?? '').trim().isEmpty
                    ? 'Pesanan dibatalkan.'
                    : 'Pesanan dibatalkan. Alasan: ${o.cancelReason}',
                style: const TextStyle(color: AppColors.error),
              ),
            )
          else ...[
            _StatusSteps(status: o.status),
            const SizedBox(height: 8),
            Text(
              _hint(o.status),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (_isInternal && (customer.isNotEmpty || processor.isNotEmpty)) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    if (customer.isNotEmpty)
                      _InfoRow(
                        label: 'Pemesan',
                        value: username.isEmpty
                            ? customer
                            : '$customer (@$username)',
                      ),
                    if (processor.isNotEmpty)
                      _InfoRow(label: 'Diproses oleh', value: processor),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final it in o.items) _itemRow(o, it),
                  const Divider(color: AppColors.border, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        Formatters.rupiah(o.total),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.yellow,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if ((o.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Catatan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              o.note!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(OrderModel o, OrderItemModel it) {
    final stock = _stock[it.productId];
    final showStock =
        _isInternal && o.status == OrderStatus.ordered && stock != null;
    final short = showStock && stock < it.qty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.productName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${it.qty} × ${Formatters.rupiah(it.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (showStock)
                  Text(
                    short
                        ? 'Stok tidak cukup (tersisa $stock)'
                        : 'Stok saat ini: $stock',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: short ? AppColors.error : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            Formatters.rupiah(it.subtotal),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Dialog alasan pembatalan. Menutup dengan teks alasan, atau null bila batal.
class _CancelDialog extends StatefulWidget {
  final bool returnsStock;

  const _CancelDialog({required this.returnsStock});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final r = _reason.text.trim();
    if (r.length < 3) {
      setState(() => _error = 'Alasan minimal 3 karakter');
      return;
    }
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Batalkan pesanan?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.returnsStock
                ? 'Pesanan sudah diproses, jadi stok akan dikembalikan.'
                : 'Pesanan belum diproses, stok tidak berubah.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 200,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Alasan pembatalan',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kembali'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 44),
            foregroundColor: AppColors.error,
          ),
          onPressed: _submit,
          child: const Text('Batalkan Pesanan'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSteps extends StatelessWidget {
  final String status;

  const _StatusSteps({required this.status});

  static const _steps = [
    OrderStatus.ordered,
    OrderStatus.processing,
    OrderStatus.done,
  ];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexOf(status);
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Expanded(
            child: Column(
              children: [
                Icon(
                  i <= current
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: i <= current
                      ? AppColors.yellow
                      : AppColors.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: i == current
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: i <= current
                        ? AppColors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
