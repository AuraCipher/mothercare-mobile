import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';
import '../utils/chat_landing_layout.dart';

/// Wireframe: `other-contacts.png` — avatar, title, preview, time, unread.
class ContactChatTile extends StatelessWidget {
  const ContactChatTile({
    super.key,
    required this.room,
    required this.onTap,
    this.preview,
  });

  final ChatRoomSummary room;
  final VoidCallback onTap;
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final initials = initialsForLabel(room.name);
    final avatarColor = avatarColorForLabel(room.name);
    final timeLabel = formatChatTime(room.lastMessageAt);
    final subtitle = preview ?? previewForRoom(room);

    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor,
                child: room.kind == 'system_attendance' || room.kind == 'system_payment'
                    ? Icon(
                        room.kind == 'system_payment' ? Icons.receipt_long_rounded : Icons.apartment_rounded,
                        color: Colors.white,
                        size: 22,
                      )
                    : Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeLabel.isNotEmpty)
                    Text(
                      timeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: room.unreadCount > 0 ? AppColors.violet : AppColors.textMuted,
                        fontWeight: room.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (room.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.violet,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    )
                  else if (room.lastMessageAt != null)
                    Icon(Icons.done_all_rounded, size: 18, color: AppColors.violet.withValues(alpha: 0.7)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
