import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/order_model.dart';
import '../../services/api_client.dart';
import '../../services/order_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/order_card.dart';
import 'order_detail_screen.dart';

/// Tab "Transaksi" untuk User internal: pesanan masuk per status.
class OrdersManageScreen extends StatelessWidget {
  const OrdersManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: OrderStatus.all.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pesanan Masuk'),
          bottom: TabBar(
            indicatorColor: AppColors.yellow,
            labelColor: AppColors.yellow,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [for (final s in OrderStatus.all) Tab(text: s)],
          ),
        ),
        body: TabBarView(
          children: [for (final s in OrderStatus.all) _OrderList(status: s)],
        ),
      ),
    );
  }
}

class _OrderList extends StatefulWidget {
  final String status;

  const _OrderList({required this.status});

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  List<OrderModel> _orders = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true; // tab tidak memuat ulang saat digeser

  @override
  void initState() {
    super.initState();
    OrderService.instance.changes.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    OrderService.instance.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load();

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await OrderService.instance.fetchByStatus(
        widget.status,
        limit: _pageSize,
        offset: more ? _orders.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _orders = more ? [..._orders, ...page] : page;
        _hasMore = page.length == _pageSize;
        _error = null;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final hadData = _orders.isNotEmpty;
      setState(() {
        _error = e.message;
        _loading = false;
        _loadingMore = false;
      });
      if (hadData) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memuat: ${e.message}')));
      }
    }
  }

  Future<void> _open(OrderModel o) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
    if (mounted) _load(); // status bisa berubah dari halaman detail
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // wajib untuk AutomaticKeepAliveClientMixin

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
      onRefresh: () => _load(),
      child: _orders.isEmpty
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum ada pesanan',
                    message:
                        'Tidak ada pesanan ${widget.status.toLowerCase()}. '
                        'Tarik ke bawah untuk memuat ulang.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _orders.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _loadingMore
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.yellow,
                                ),
                              ),
                            ],
                          )
                        : TextButton(
                            onPressed: () => _load(more: true),
                            child: const Text('Muat lebih banyak'),
                          ),
                  );
                }
                final o = _orders[i];
                return OrderCard(
                  order: o,
                  showCustomer: true,
                  onTap: () => _open(o),
                );
              },
            ),
    );
  }
}
