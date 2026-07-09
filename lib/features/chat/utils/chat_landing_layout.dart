import 'package:flutter/material.dart';

import '../models/chat_models.dart';

/// Maps API landing data into the four UI blocks from wireframes.
class ChatLandingLayout {
  const ChatLandingLayout(this.data);

  final ChatLandingData data;

  ChatRoomSummary? get schoolAnnouncement {
    for (final room in data.rooms) {
      if (room.kind == 'school_announcement') return room;
    }
    return null;
  }

  /// Single "Class Group" entry tile on the landing page.
  ChatRoomSummary? get classGroupEntry {
    for (final room in data.rooms) {
      if (room.kind == 'class_announcement') return room;
    }
    for (final room in data.rooms) {
      if (room.kind == 'group_chat') return room;
    }
    return null;
  }

  /// Full class community (announcement + subject groups + system feeds).
  List<ChatRoomSummary> get classCommunityRooms {
    const kinds = {
      'class_announcement',
      'group_chat',
      'system_attendance',
      'system_payment',
    };
    return data.rooms.where((r) => kinds.contains(r.kind)).toList();
  }

  /// Contacts / chats list — DMs and system channels below class group.
  List<ChatRoomSummary> get contactRooms {
    const kinds = {'direct_message', 'system_attendance', 'system_payment'};
    return data.rooms.where((r) => kinds.contains(r.kind)).toList();
  }

  int get totalUnread {
    return data.rooms.fold(0, (sum, r) => sum + r.unreadCount);
  }
}

String initialsForLabel(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.length >= 2
        ? parts.first.substring(0, 2).toUpperCase()
        : parts.first.toUpperCase();
  }
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}

Color avatarColorForLabel(String name) {
  const palette = [
    Color(0xFF6C63FF),
    Color(0xFF4ECDC4),
    Color(0xFFFF6B6B),
    Color(0xFFF59E0B),
    Color(0xFF5248E8),
    Color(0xFF10B981),
  ];
  return palette[name.hashCode.abs() % palette.length];
}

String previewForRoom(ChatRoomSummary room, {String? groupLabel}) {
  if (room.description != null && room.description!.trim().isNotEmpty) {
    return room.description!.trim();
  }
  switch (room.kind) {
    case 'school_announcement':
      return 'School-wide announcements';
    case 'class_announcement':
      return groupLabel != null ? '$groupLabel announcements' : 'Class announcements';
    case 'group_chat':
      return 'Subject group chat';
    case 'system_attendance':
      return 'Daily attendance updates';
    case 'system_payment':
      return 'Fee payments and receipts';
    case 'direct_message':
      return 'Direct message';
    default:
      return 'Tap to open';
  }
}

String formatChatTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  if (msgDay == today) {
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final min = local.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }
  if (msgDay == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (now.difference(local).inDays < 7) {
    return weekdays[local.weekday - 1];
  }
  return '${local.day}/${local.month}';
}
