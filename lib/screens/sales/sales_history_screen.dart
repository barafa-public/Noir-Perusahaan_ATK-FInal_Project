import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/sale_model.dart';
import '../../services/db_helper.dart';
import '../../services/sale_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/empty_state.dart';
import '../../services/time_service.dart';

/// Riwayat penjualan dari SQLite: milik perangkat ini (termasuk yang belum
/// terkirim) dan penjualan perangkat lain yang sudah ditarik dari server.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  static const _pageSize = 50;

  List<SaleModel> _sales = const [];
  bool _loaded = false;
  bool _hasMore = false;
  int _pending = 0;
  int _rejected = 0;
  ({int count, int total}) _today = (count: 0, total: 0);

    @override
  void initState() {
    super.initState();
    SyncService.instance.salesChanged.addListener(_load);
    TimeService.instance.displayZone.addListener(_load);
    _load();
    SyncService.instance.syncAll(); // tarik penjualan terbaru saat dibuka
  }

  @override
  void dispose() {
    SyncService.instance.salesChanged.removeListener(_load);
    TimeService.instance.displayZone.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = DbHelper.instance;
    final now = DateTime.now();
    final startOfDay = SaleModel.normalizeIso(
      TimeService.startOfDayUtc(
        TimeService.instance.displayZone.value,
        DateTime.now().toUtc(),
      ),
    );

    final sales = await db.getSales(limit: _pageSize);
    final today = await db.getSalesSince(startOfDay);
    final pending = await db.countAllPendingSales();
    final rejected = await db.countRejectedSales();
    if (!mounted) return;

    setState(() {
      _sales = sales;
      _hasMore = sales.length == _pageSize;
      _today = today;
      _pending = pending;
      _rejected = rejected;
      _loaded = true;
    });
  }

  Future<void> _loadMore() async {
    final more = await DbHelper.instance.getSales(
      limit: _pageSize,
      offset: _sales.length,
    );
    if (!mounted) return;
    setState(() {
      _sales = [..._sales, ...more];
      _hasMore = more.length == _pageSize;
    });
  }

  Future<void> _refresh() async {
    final report = await SyncService.instance.syncAll();
    await _load();
    if (!mounted) return;
    if (report.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkronisasi gagal: ${report.error}')),
      );
    }
  }

  Future<void> _onTapSale(SaleModel s) async {
    if (!s.isRejected) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.productName} × ${s.qty}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ditolak server: ${s.syncError}',
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 4),
              const Text(
                'Stok tidak berkurang untuk penjualan ini.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.yellow,
                ),
                title: const Text('Kirim ulang'),
                onTap: () => Navigator.of(ctx).pop('retry'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: const Text('Hapus dari perangkat'),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'retry') {
      await SaleService.instance.retry(s.id);
    } else if (action == 'delete') {
      await SaleService.instance.discardRejected(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Penjualan')),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.yellow),
            )
          : RefreshIndicator(
              color: AppColors.yellow,
              backgroundColor: AppColors.surface,
              onRefresh: _refresh,
              child: _sales.isEmpty
                  ? CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: const [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.point_of_sale_rounded,
                            title: 'Belum ada penjualan',
                            message:
                                'Penjualan yang dicatat akan muncul di sini.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _sales.length + 2 + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == 0) return _buildHeader();
                        if (i == 1) return _buildNotices();
                        final idx = i - 2;
                        if (idx == _sales.length) {
                          return TextButton(
                            onPressed: _loadMore,
                            child: const Text('Muat lebih banyak'),
                          );
                        }
                        return _SaleTile(
                          sale: _sales[idx],
                          onTap: () => _onTapSale(_sales[idx]),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Penjualan hari ini',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.rupiah(_today.total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.yellow,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_today.count} transaksi',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotices() {
    if (_pending == 0 && _rejected == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (_pending > 0)
            _Notice(
              color: AppColors.yellow,
              text:
                  '$_pending penjualan menunggu dikirim ke server. '
                  'Tarik ke bawah untuk mencoba lagi.',
            ),
          if (_rejected > 0) ...[
            if (_pending > 0) const SizedBox(height: 8),
            _Notice(
              color: AppColors.error,
              text:
                  '$_rejected penjualan ditolak server. '
                  'Ketuk untuk kirim ulang atau hapus.',
            ),
          ],
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final SaleModel sale;
  final VoidCallback onTap;

  const _SaleTile({required this.sale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final Color statusColor;
    final String statusText;
    if (s.synced) {
      statusColor = AppColors.success;
      statusText = 'Terkirim';
    } else if (s.isRejected) {
      statusColor = AppColors.error;
      statusText = 'Ditolak';
    } else {
      statusColor = AppColors.yellow;
      statusText = 'Menunggu';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s.isRejected ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.qty} × ${Formatters.rupiah(s.unitPrice)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(s.soldAt),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.rupiah(s.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: s.isRejected
                          ? AppColors.textSecondary
                          : AppColors.yellow,
                      decoration: s.isRejected
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final String text;

  const _Notice({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
