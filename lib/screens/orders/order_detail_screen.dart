import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order_model.dart';
import '../../services/api_client.dart';
import '../../services/order_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/order_status_chip.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderModel? _order;
  bool _loading = true;
  String? _error;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Pesanan')),
      body: body,
    );
  }

  Widget _buildContent(OrderModel o) {
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
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final it in o.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${it.qty} × ${Formatters.rupiah(it.unitPrice)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
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
                    ),
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
