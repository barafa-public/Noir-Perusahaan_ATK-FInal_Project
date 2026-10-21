import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../services/auth_service.dart';
import '../../services/db_helper.dart';
import '../../services/product_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/product_card.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  String? _category;
  List<ProductModel> _products = const [];
  List<String> _categories = const [];
  bool _loaded = false;
  int _seq = 0; // mencegah hasil query lama menimpa yang baru

  bool get _isInternal => AuthService.instance.user?.isInternal ?? false;
  bool get _filtering => _search.text.trim().isNotEmpty || _category != null;

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

  /// Membaca dari cache SQLite, jadi katalog tetap tampil saat offline.
  Future<void> _load() async {
    final seq = ++_seq;
    final db = DbHelper.instance;

    final categories = await db.getCategories();
    if (!mounted || seq != _seq) return;

    // Kategori yang dipilih sudah tidak ada (produknya dinonaktifkan).
    if (_category != null && !categories.contains(_category)) {
      _category = null;
      return _load();
    }

    final products = await db.getProducts(
      query: _search.text,
      category: _category,
    );
    if (!mounted || seq != _seq) return;

    setState(() {
      _categories = categories;
      _products = products;
      _loaded = true;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _setCategory(String? category) {
    setState(() => _category = category);
    _load();
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

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<ProductModel>(
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${saved.name} ditambahkan.')));
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppColors.yellow,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: TextStyle(
          color: selected ? AppColors.black : AppColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildList() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.yellow),
      );
    }

    return RefreshIndicator(
      color: AppColors.yellow,
      backgroundColor: AppColors.surface,
      onRefresh: _refresh,
      child: _products.isEmpty
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: _filtering
                        ? Icons.search_off_rounded
                        : Icons.inventory_2_outlined,
                    title: _filtering
                        ? 'Produk tidak ditemukan'
                        : 'Belum ada produk',
                    message: _filtering
                        ? 'Coba kata kunci atau kategori lain.'
                        : 'Tarik ke bawah untuk memuat ulang.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, _isInternal ? 96 : 16),
              itemCount: _products.length,
              itemBuilder: (context, i) {
                final p = _products[i];
                return ProductCard(
                  product: p,
                  showLowStock: _isInternal,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(productId: p.id),
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
      appBar: AppBar(title: Text(_isInternal ? 'Produk & Stok' : 'Produk')),
      floatingActionButton: _isInternal
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: AppColors.yellow,
              foregroundColor: AppColors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Produk'),
            )
          : null,
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('Semua', _category == null, () => _setCategory(null)),
                for (final c in _categories)
                  _chip(c, _category == c, () => _setCategory(c)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}
