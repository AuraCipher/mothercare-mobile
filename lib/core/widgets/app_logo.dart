import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

abstract final class AppAssets {
  static const logo = 'assets/logo.png';
}

/// Mother Care logo — used on login, splash, and headers.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 56,
    this.borderRadius = 16,
    this.showBackground = true,
  });

  final double size;
  final double borderRadius;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        AppAssets.logo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.school_rounded,
          size: size * 0.55,
          color: AppColors.violet,
        ),
      ),
    );

    if (!showBackground) return image;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: image,
    );
  }
}
