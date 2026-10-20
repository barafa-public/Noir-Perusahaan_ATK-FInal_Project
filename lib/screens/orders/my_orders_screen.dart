import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order_model.dart';
import '../../services/api_client.dart';
import '../../services/order_service.dart';
import '../../widgets/cart_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/order_status_chip.dart';
import 'order_detail_screen.dart';

/// Tab "Pesanan" untuk Customer: riwayat dan status pesanan.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<OrderModel> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    OrderService.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    OrderService.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await OrderService.instance.fetchMine();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final hadData = _orders.isNotEmpty;
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    }
    if (_error != null && _orders.isEmpty) {
      return ErrorView(
        message: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }

    return RefreshIndicator(
      color: AppColors.yellow,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: _orders.isEmpty
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Belum ada pesanan',
                    message: 'Pesanan yang kamu buat akan muncul di sini.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (context, i) {
                final o = _orders[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(orderId: o.id),
                        ),
                      );
                      if (mounted) _load(); // status bisa berubah
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.orderNo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  Formatters.dateTime(o.createdAt),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              OrderStatusChip(o.status),
                              const SizedBox(height: 8),
                              Text(
                                Formatters.rupiah(o.total),
                                style: const TextStyle(
                                  color: AppColors.yellow,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan Saya'),
        actions: const [CartButton()],
      ),
      body: _buildBody(),
    );
  }
}
