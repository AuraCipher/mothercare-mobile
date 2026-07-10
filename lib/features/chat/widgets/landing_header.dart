import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_config.dart';
import '../../../core/theme/app_theme.dart';

/// App bar matching mockup structure — built with theme tokens, not reference images.
class LandingHeader extends StatelessWidget {
  const LandingHeader({
    super.key,
    this.onSearch,
    this.onMenu,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onMenu;

  static const double _barHeight = 56;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Container(
        height: top + _barHeight,
        padding: EdgeInsets.only(top: top, left: 16, right: 4),
        decoration: const BoxDecoration(
          color: AppColors.violet,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppConfig.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              tooltip: 'Search',
            ),
            IconButton(
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              tooltip: 'Menu',
            ),
          ],
        ),
      ),
    );
  }
}
