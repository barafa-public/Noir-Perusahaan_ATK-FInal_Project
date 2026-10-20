import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../models/product_model.dart';
import '../screens/products/product_detail_screen.dart';
import '../services/db_helper.dart';
import '../services/product_service.dart';

/// Ringkasan stok di Beranda User internal, dibaca dari cache SQLite
/// (stok efektif) dan ikut diperbarui setiap kali data produk berubah.
class StockSummaryCard extends StatefulWidget {
  const StockSummaryCard({super.key});

  @override
  State<StockSummaryCard> createState() => _StockSummaryCardState();
}

class _StockSummaryCardState extends State<StockSummaryCard> {
  StockSummary _summary = const StockSummary();
  List<ProductModel> _low = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ProductService.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ProductService.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final summary = await DbHelper.instance.getStockSummary();
    final low = await DbHelper.instance.getLowStockProducts(limit: 5);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _low = low;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppColors.yellow),
                SizedBox(width: 10),
                Text(
                  'Ringkasan stok',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_loaded)
              const LinearProgressIndicator(color: AppColors.yellow)
            else if (_summary.total == 0)
              const Text(
                'Belum ada data produk. Tarik layar ke bawah untuk menyinkronkan.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      value: _summary.total,
                      label: 'Produk',
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      value: _summary.low,
                      label: 'Menipis',
                      color: _summary.low > 0
                          ? AppColors.yellow
                          : AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      value: _summary.out,
                      label: 'Habis',
                      color: _summary.out > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
              if (_low.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Perlu restock',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                for (final p in _low)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(productId: p.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.isOutOfStock
                                ? 'Habis'
                                : 'Sisa ${p.stock} / min ${p.minStock}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: p.isOutOfStock
                                  ? AppColors.error
                                  : AppColors.yellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
