import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';
import 'room_list_icon.dart';

class ChatRoomTile extends StatelessWidget {
  const ChatRoomTile({
    super.key,
    required this.room,
    required this.onTap,
    this.displayName,
    this.subtitle,
  });

  final ChatRoomSummary room;
  final VoidCallback onTap;
  final String? displayName;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final timeLabel = room.lastMessageAt != null
        ? DateFormat('MMM d, h:mm a').format(room.lastMessageAt!.toLocal())
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              RoomListIcon(room: room),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName ?? room.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ] else if (timeLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (room.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.violet,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
