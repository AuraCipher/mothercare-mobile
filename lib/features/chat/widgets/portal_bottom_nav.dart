import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum PortalNavTab { chats, workspace, profile }

class PortalBottomNav extends StatelessWidget {
  const PortalBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
    this.workspaceLabel = 'Classes',
    this.workspaceIcon = Icons.class_outlined,
    this.workspaceSelectedIcon = Icons.class_rounded,
  });

  final PortalNavTab current;
  final ValueChanged<PortalNavTab> onChanged;
  final String workspaceLabel;
  final IconData workspaceIcon;
  final IconData workspaceSelectedIcon;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: current.index,
      onDestinationSelected: (i) => onChanged(PortalNavTab.values[i]),
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.violet.withValues(alpha: 0.12),
      height: 72,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded, color: AppColors.violet),
          label: 'Chats',
        ),
        NavigationDestination(
          icon: Icon(workspaceIcon),
          selectedIcon: Icon(workspaceSelectedIcon, color: AppColors.violet),
          label: workspaceLabel,
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: AppColors.violet),
          label: 'Profile',
        ),
      ],
    );
  }
}
