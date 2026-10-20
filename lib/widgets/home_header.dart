import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/auth_service.dart';
import 'user_avatar.dart';

class HomeHeader extends StatelessWidget {
  final String subtitle;
  const HomeHeader({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;

    return Row(
      children: [
        const UserAvatar(size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Halo, ${user?.fullName ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
