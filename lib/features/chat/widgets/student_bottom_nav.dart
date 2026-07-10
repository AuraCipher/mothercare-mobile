import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum StudentNavTab { chats, academics, profile }

class StudentBottomNav extends StatelessWidget {
  const StudentBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
    this.chatUnread = 0,
  });

  final StudentNavTab current;
  final ValueChanged<StudentNavTab> onChanged;
  final int chatUnread;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: current.index,
      onDestinationSelected: (i) => onChanged(StudentNavTab.values[i]),
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.violet.withValues(alpha: 0.12),
      height: 72,
      destinations: [
        NavigationDestination(
          icon: Badge(
            isLabelVisible: chatUnread > 0,
            label: Text(chatUnread > 99 ? '99+' : '$chatUnread'),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          selectedIcon: const Icon(Icons.chat_bubble_rounded, color: AppColors.violet),
          label: 'Chats',
        ),
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book_rounded, color: AppColors.violet),
          label: 'Academics',
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
