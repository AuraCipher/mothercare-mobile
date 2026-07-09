import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum StudentNavTab { chats, communities, profile }

/// Bottom navigation from str-preview wireframes.
class StudentBottomNav extends StatelessWidget {
  const StudentBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
    this.chatsBadge = 0,
  });

  final StudentNavTab current;
  final ValueChanged<StudentNavTab> onChanged;
  final int chatsBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _NavItem(
                label: 'Chats',
                icon: Icons.chat_bubble_rounded,
                selected: current == StudentNavTab.chats,
                badge: chatsBadge,
                onTap: () => onChanged(StudentNavTab.chats),
              ),
              _NavItem(
                label: 'Communities',
                icon: Icons.groups_rounded,
                selected: current == StudentNavTab.communities,
                onTap: () => onChanged(StudentNavTab.communities),
              ),
              _NavItem(
                label: 'Profile',
                icon: Icons.person_rounded,
                selected: current == StudentNavTab.profile,
                onTap: () => onChanged(StudentNavTab.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.violet : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.violet.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  if (badge > 0 && selected)
                    Positioned(
                      right: 8,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.violet,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
