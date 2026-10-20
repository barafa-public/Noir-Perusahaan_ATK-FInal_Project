import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../screens/cart/cart_screen.dart';
import '../services/cart_service.dart';

/// Ikon keranjang dengan lencana jumlah, untuk AppBar Customer.
class CartButton extends StatefulWidget {
  const CartButton({super.key});

  @override
  State<CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends State<CartButton> {
  @override
  void initState() {
    super.initState();
    CartService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final n = CartService.instance.totalQty;
        return IconButton(
          tooltip: 'Keranjang',
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CartScreen())),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            backgroundColor: AppColors.yellow,
            textColor: AppColors.black,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
        );
      },
    );
  }
}
