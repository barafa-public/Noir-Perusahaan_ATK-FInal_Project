import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/api_client.dart';
import '../../services/cart_service.dart';
import '../../services/order_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/empty_state.dart';
import '../orders/order_detail_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _note = TextEditingController();

  bool _syncing = true;
  bool _placing = false;
  String? _syncError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshPrices();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Menarik harga dan stok terbaru dari server sebelum ringkasan ditampilkan.
  Future<void> _refreshPrices() async {
    String? err;
    try {
      await SyncService.instance.syncProducts();
    } on ApiException catch (e) {
      err = e.message;
    }
    await CartService.instance.load();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncError = err;
    });
  }

  Future<void> _placeOrder() async {
    if (_placing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _placing = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      final order = await OrderService.instance.create(
        CartService.instance.lines,
        note: _note.text,
      );
      await CartService.instance.clear();
      if (!mounted) return;

      nav.popUntil((r) => r.isFirst);
      nav.push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Pesanan ${order.orderNo} dibuat.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // Tanpa status HTTP = koneksi putus; pesanan mungkin sudah tercatat server.
      final msg = e.statusCode == null
          ? '${e.message} Cek daftar pesanan sebelum mencoba lagi agar '
                'tidak terjadi pesanan ganda.'
          : e.message;
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Pesanan')),
      body: _syncing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.yellow),
                  SizedBox(height: 16),
                  Text(
                    'Memperbarui harga dari server...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListenableBuilder(
              listenable: CartService.instance,
              builder: (context, _) => _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    final cart = CartService.instance;
    if (cart.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'Keranjang kosong',
        message: 'Tambahkan produk dari halaman Produk.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_syncError != null) ...[
                _Banner(
                  color: AppColors.yellow,
                  text:
                      'Harga belum bisa diperbarui ($_syncError). '
                      'Harga final tetap ditentukan server saat pesanan dibuat.',
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final l in cart.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${l.qty} × ${Formatters.rupiah(l.product.price)}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (l.exceedsStock)
                                      Text(
                                        l.product.stock <= 0
                                            ? 'Stok habis'
                                            : 'Stok tersisa ${l.product.stock}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.error,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                Formatters.rupiah(l.subtotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
                            Formatters.rupiah(cart.total),
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
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                enabled: !_placing,
                maxLines: 2,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Total final dihitung server saat pesanan dibuat. '
                'Stok baru dikurangi ketika toko memproses pesanan.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _Banner(color: AppColors.error, text: _error!),
              ],
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.black,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: FilledButton(
                onPressed: _placing ? null : _placeOrder,
                child: _placing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.black,
                        ),
                      )
                    : const Text('Buat Pesanan'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final String text;

  const _Banner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
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
