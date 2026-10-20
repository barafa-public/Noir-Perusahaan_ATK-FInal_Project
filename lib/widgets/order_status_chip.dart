import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../models/order_model.dart';

class OrderStatusChip extends StatelessWidget {
  final String status;

  const OrderStatusChip(this.status, {super.key});

  static Color colorOf(String status) => switch (status) {
    OrderStatus.ordered => AppColors.yellow,
    OrderStatus.processing => const Color(0xFF6CB6FF),
    OrderStatus.done => AppColors.success,
    OrderStatus.cancelled => AppColors.error,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
