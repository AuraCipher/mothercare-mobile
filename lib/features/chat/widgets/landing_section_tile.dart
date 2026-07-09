import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Wireframe: `school-announcement.png` / `class-community.png` row style.
class LandingSectionTile extends StatelessWidget {
  const LandingSectionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
    this.leadingBackground,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final VoidCallback onTap;
  final Color? leadingBackground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: leadingBackground ?? AppColors.violet.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: leading,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
