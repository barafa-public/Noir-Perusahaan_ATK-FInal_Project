import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/cart_item_model.dart';
import '../../services/cart_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/qty_stepper.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    CartService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: ListenableBuilder(
        listenable: CartService.instance,
        builder: (context, _) {
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
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: cart.lines.length,
                  itemBuilder: (_, i) => _CartTile(item: cart.lines[i]),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Perkiraan total',
                              style: TextStyle(color: AppColors.textSecondary),
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
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CheckoutScreen(),
                            ),
                          ),
                          child: const Text('Lanjut ke Pesanan'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  final CartItemModel item;

  const _CartTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final cart = CartService.instance;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.rupiah(p.price),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (item.exceedsStock) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.stock <= 0 ? 'Stok habis' : 'Stok tersisa ${p.stock}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    Formatters.rupiah(item.subtotal),
                    style: const TextStyle(
                      color: AppColors.yellow,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                QtyStepper(
                  value: item.qty,
                  onMinus: () => cart.setQty(p.id, item.qty - 1),
                  onPlus: item.qty < p.stock
                      ? () => cart.setQty(p.id, item.qty + 1)
                      : null,
                ),
                TextButton.icon(
                  onPressed: () => cart.remove(p.id),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Hapus'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
