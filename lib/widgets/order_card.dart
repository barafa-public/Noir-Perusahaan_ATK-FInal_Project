import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/order_model.dart';
import 'order_status_chip.dart';

/// Kartu ringkas satu pesanan untuk daftar.
class OrderCard extends StatelessWidget {
  final OrderModel order;
  final bool showCustomer;
  final VoidCallback onTap;

  const OrderCard({
    super.key,
    required this.order,
    required this.onTap,
    this.showCustomer = false,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final customer = (o.customerName ?? '').trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.orderNo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (showCustomer && customer.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(o.createdAt),
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
                  OrderStatusChip(o.status),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.rupiah(o.total),
                    style: const TextStyle(
                      color: AppColors.yellow,
                      fontWeight: FontWeight.w800,
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
