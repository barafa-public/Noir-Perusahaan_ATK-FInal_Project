import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/product_model.dart';
import '../../services/db_helper.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductModel? _product;
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
    final p = await DbHelper.instance.getProduct(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = p;
      _loaded = true;
    });
  }

  Future<void> _edit(ProductModel p) async {
    final saved = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Perubahan disimpan.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Produk'),
        actions: [
          if (p != null)
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(p),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.yellow),
            )
          : p == null
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Produk tidak tersedia',
                  message:
                      'Produk ini sudah dinonaktifkan atau belum tersinkron.',
                )
              : _buildContent(p),
    );
  }

  Widget _buildContent(ProductModel p) {
    final String statusText;
    final Color statusColor;
    if (p.isOutOfStock) {
      statusText = 'Habis';
      statusColor = AppColors.error;
    } else if (p.isLowStock) {
      statusText = 'Stok menipis';
      statusColor = AppColors.yellow;
    } else {
      statusText = 'Tersedia';
      statusColor = AppColors.success;
    }

    final description = (p.description ?? '').trim();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.yellow,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          p.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [_Pill(p.category), _Pill(p.sku)],
        ),
        const SizedBox(height: 16),
        Text(
          Formatters.rupiah(p.price),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.yellow,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _InfoRow(
                  label: 'Status',
                  value: statusText,
                  valueColor: statusColor,
                ),
                _InfoRow(label: 'Stok', value: '${p.stock}'),
                _InfoRow(label: 'Stok minimum', value: '${p.minStock}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Deskripsi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          description.isEmpty ? '-' : description,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
