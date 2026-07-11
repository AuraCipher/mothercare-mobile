import 'package:flutter/material.dart';

import '../models/chat_models.dart';

/// Light pastel tile icons — theme colors, not emoji.
class RoomListIcon extends StatelessWidget {
  const RoomListIcon({
    super.key,
    required this.room,
    this.size = 44,
  });

  final ChatRoomSummary room;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = roomIconStyle(room);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(style.icon, color: style.foreground, size: size * 0.5),
    );
  }
}

class RoomIconStyle {
  const RoomIconStyle({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

RoomIconStyle roomIconStyle(ChatRoomSummary room) {
  switch (room.kind) {
    case 'school_announcement':
      return const RoomIconStyle(
        icon: Icons.campaign_rounded,
        background: Color(0xFFF3E8FF),
        foreground: Color(0xFF7C3AED),
      );
    case 'class_announcement':
      return const RoomIconStyle(
        icon: Icons.groups_rounded,
        background: Color(0xFFE8F4FF),
        foreground: Color(0xFF2563EB),
      );
    case 'system_attendance':
      return const RoomIconStyle(
        icon: Icons.fact_check_rounded,
        background: Color(0xFFE6F7F1),
        foreground: Color(0xFF059669),
      );
    case 'system_payment':
      return const RoomIconStyle(
        icon: Icons.account_balance_wallet_rounded,
        background: Color(0xFFFFF4E5),
        foreground: Color(0xFFD97706),
      );
    case 'system_result':
      return const RoomIconStyle(
        icon: Icons.emoji_events_rounded,
        background: Color(0xFFEEF2FF),
        foreground: Color(0xFF4F46E5),
      );
    case 'system_teacher_attendance':
      return const RoomIconStyle(
        icon: Icons.fact_check_rounded,
        background: Color(0xFFE6F7F1),
        foreground: Color(0xFF059669),
      );
    case 'system_teacher_payroll':
      return const RoomIconStyle(
        icon: Icons.payments_rounded,
        background: Color(0xFFFFF4E5),
        foreground: Color(0xFFD97706),
      );
    case 'direct_message':
      return const RoomIconStyle(
        icon: Icons.chat_bubble_rounded,
        background: Color(0xFFFFE8F0),
        foreground: Color(0xFFDB2777),
      );
    case 'group_chat':
      return _subjectStyle(room.name);
    default:
      return const RoomIconStyle(
        icon: Icons.forum_rounded,
        background: Color(0xFFEEEEF8),
        foreground: Color(0xFF6C63FF),
      );
  }
}

const _subjectPalettes = [
  RoomIconStyle(
    icon: Icons.menu_book_rounded,
    background: Color(0xFFEEF2FF),
    foreground: Color(0xFF4F46E5),
  ),
  RoomIconStyle(
    icon: Icons.science_rounded,
    background: Color(0xFFE0F7FA),
    foreground: Color(0xFF0891B2),
  ),
  RoomIconStyle(
    icon: Icons.calculate_rounded,
    background: Color(0xFFFFF7ED),
    foreground: Color(0xFFEA580C),
  ),
  RoomIconStyle(
    icon: Icons.language_rounded,
    background: Color(0xFFF0FDF4),
    foreground: Color(0xFF16A34A),
  ),
  RoomIconStyle(
    icon: Icons.palette_rounded,
    background: Color(0xFFFDF2F8),
    foreground: Color(0xFFBE185D),
  ),
  RoomIconStyle(
    icon: Icons.history_edu_rounded,
    background: Color(0xFFF5F3FF),
    foreground: Color(0xFF7C3AED),
  ),
];

RoomIconStyle _subjectStyle(String subjectName) {
  final i = subjectName.hashCode.abs() % _subjectPalettes.length;
  return _subjectPalettes[i];
}

IconData iconDataForRoomKind(String kind) => roomIconStyle(
      ChatRoomSummary(id: '', kind: kind, name: '', canPost: false, unreadCount: 0),
    ).icon;
