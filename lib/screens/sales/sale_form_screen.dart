import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/product_model.dart';
import '../../services/db_helper.dart';
import '../../services/product_service.dart';
import '../../services/sale_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/product_card.dart';
import '../../widgets/qty_stepper.dart';

/// Catat penjualan langsung: cari dan pilih produk, atur jumlah, simpan.
/// Satu penjualan = satu produk; untuk beberapa produk, catat satu per satu.
class SaleFormScreen extends StatefulWidget {
  const SaleFormScreen({super.key});

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<ProductModel> _products = const [];
  ProductModel? _selected;
  int _qty = 1;
  bool _loaded = false;
  bool _saving = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    ProductService.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ProductService.instance.changes.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final list = await DbHelper.instance.getProducts(query: _search.text);

    // Segarkan produk terpilih (stok efektif bisa berubah setelah sinkronisasi).
    ProductModel? selected = _selected;
    if (selected != null) {
      selected = await DbHelper.instance.getProduct(selected.id);
    }
    if (!mounted || seq != _seq) return;

    setState(() {
      _products = list;
      if (selected == null || selected.stock <= 0) {
        _selected = null; // dihapus/habis setelah sinkronisasi
        _qty = 1;
      } else {
        _selected = selected;
        if (_qty > selected.stock) _qty = selected.stock;
      }
      _loaded = true;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _select(ProductModel p) {
    FocusScope.of(context).unfocus();
    if (p.stock <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Stok ${p.name} habis.')));
      return;
    }
    setState(() {
      _selected = p;
      _qty = 1;
    });
  }

  Future<void> _save() async {
    final p = _selected;
    if (p == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sale = await SaleService.instance.record(
        productId: p.id,
        qty: _qty,
      );
      if (!mounted) return;
      setState(() {
        _selected = null;
        _qty = 1;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Penjualan tercatat: ${sale.productName} × ${sale.qty} '
            '(${Formatters.rupiah(sale.total)}) · '
            '${Formatters.dateTime(sale.soldAt)}.',
          ),
        ),
      );
    } on SaleException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) _load(); // stok mungkin berubah
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildList() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    }
    if (_products.isEmpty) {
      return EmptyState(
        icon: _search.text.trim().isEmpty
            ? Icons.inventory_2_outlined
            : Icons.search_off_rounded,
        title: _search.text.trim().isEmpty
            ? 'Belum ada produk'
            : 'Produk tidak ditemukan',
        message: _search.text.trim().isEmpty
            ? 'Sinkronkan data produk dari tab Produk.'
            : 'Coba kata kunci lain.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _products.length,
      itemBuilder: (context, i) {
        final p = _products[i];
        return Opacity(
          opacity: p.stock <= 0 ? 0.5 : 1,
          child: ProductCard(product: p, onTap: () => _select(p)),
        );
      },
    );
  }

  Widget _buildSelectedPanel(ProductModel p) {
    final total = p.price * _qty;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${Formatters.rupiah(p.price)} · stok tersedia ${p.stock}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  QtyStepper(
                    value: _qty,
                    onMinus: _qty > 1 && !_saving
                        ? () => setState(() => _qty--)
                        : null,
                    onPlus: _qty < p.stock && !_saving
                        ? () => setState(() => _qty++)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      Formatters.rupiah(total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.yellow,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.black,
                        ),
                      )
                    : const Text('Catat Penjualan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Catat Penjualan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama atau SKU',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _search,
                  builder: (_, value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _load();
                          },
                        ),
                ),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
      bottomNavigationBar: selected == null
          ? null
          : _buildSelectedPanel(selected),
    );
  }
}
