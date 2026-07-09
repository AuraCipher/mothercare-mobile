import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Wireframe: `header.png` — MCS School bar with search + menu.
class StudentLandingHeader extends StatelessWidget {
  const StudentLandingHeader({
    super.key,
    this.onSearch,
    this.onMenu,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.violet,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        left: 16,
        right: 8,
        bottom: 14,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'MCS School',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
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
    );
  }
}
