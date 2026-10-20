import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// Pengatur jumlah [-] n [+]. Tombol dengan callback null dinonaktifkan.
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const QtyStepper({
    super.key,
    required this.value,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_rounded),
          ),
          // Text langsung (bukan Center): Center tanpa tinggi akan melar
          // setinggi layar bila ditaruh di bottomNavigationBar.
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}