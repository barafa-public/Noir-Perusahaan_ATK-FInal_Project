import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../services/api_client.dart';
import '../../services/db_helper.dart';
import '../../services/product_service.dart';

/// Tambah produk ([product] null) atau ubah produk. Hanya dibuka User internal;
/// server tetap menolak role lain. Menutup dengan hasil [ProductModel] bila tersimpan.
class ProductFormScreen extends StatefulWidget {
  final ProductModel? product;

  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  static const _maxPrice = 1000000000;
  static const _maxStock = 1000000;
  static final _skuRe = RegExp(r'^[A-Za-z0-9._-]{2,30}$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sku;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;

  List<String> _categories = const [];
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _sku = TextEditingController(text: p?.sku ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(text: p?.price.toString() ?? '');
    _stock = TextEditingController(text: p?.stock.toString() ?? '0');
    _minStock = TextEditingController(text: p?.minStock.toString() ?? '5');
    _loadCategories();
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final cats = await DbHelper.instance.getCategories();
    if (mounted) setState(() => _categories = cats);
  }

  String? _vSku(String? v) {
    if (_isEdit) return null;
    if (!_skuRe.hasMatch((v ?? '').trim())) {
      return 'SKU 2-30 karakter: huruf, angka, titik, minus, atau underscore';
    }
    return null;
  }

  String? _vLength(String? v, String label, int min, int max) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label wajib diisi';
    if (s.length < min) return '$label minimal $min karakter';
    if (s.length > max) return '$label maksimal $max karakter';
    return null;
  }

  String? _vInt(String? v, String label, int max) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label wajib diisi';
    final n = int.tryParse(s);
    if (n == null || n < 0) return '$label tidak valid';
    if (n > max) return '$label terlalu besar';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await ProductService.instance.save(
        id: widget.product?.id,
        sku: _sku.text.trim().toUpperCase(),
        name: _name.text.trim(),
        category: _category.text.trim(),
        description: _description.text.trim(),
        price: int.parse(_price.text.trim()),
        stock: int.parse(_stock.text.trim()),
        minStock: int.parse(_minStock.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Ubah Produk' : 'Tambah Produk')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _sku,
                  enabled: !_loading && !_isEdit,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'SKU',
                    hintText: 'ATK-011',
                    helperText: _isEdit ? 'SKU tidak dapat diubah.' : null,
                  ),
                  validator: _vSku,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  enabled: !_loading,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama produk'),
                  validator: (v) => _vLength(v, 'Nama produk', 2, 80),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _category,
                  enabled: !_loading,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    hintText: 'mis. Alat Tulis',
                  ),
                  validator: (v) => _vLength(v, 'Kategori', 2, 40),
                ),
                if (_categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _categories)
                        ActionChip(
                          label: Text(c),
                          backgroundColor: AppColors.surface,
                          side: const BorderSide(color: AppColors.border),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _category.text = c),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  enabled: !_loading,
                  maxLines: 3,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi (opsional)',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v ?? '').trim().length > 300
                      ? 'Deskripsi maksimal 300 karakter'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _price,
                  enabled: !_loading,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsOnly,
                  decoration: const InputDecoration(
                    labelText: 'Harga',
                    prefixText: 'Rp ',
                  ),
                  validator: (v) => _vInt(v, 'Harga', _maxPrice),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        inputFormatters: digitsOnly,
                        decoration: const InputDecoration(labelText: 'Stok'),
                        validator: (v) => _vInt(v, 'Stok', _maxStock),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        inputFormatters: digitsOnly,
                        decoration:
                            const InputDecoration(labelText: 'Stok minimum'),
                        validator: (v) => _vInt(v, 'Stok minimum', _maxStock),
                      ),
                    ),
                  ],
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Stok yang diisi di sini menimpa stok saat ini di server.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.black),
                        )
                      : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Produk'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
