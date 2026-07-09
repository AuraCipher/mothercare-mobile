import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../utils/chat_landing_layout.dart';
import '../widgets/contact_chat_tile.dart';
import '../widgets/landing_section_tile.dart';
import '../widgets/student_landing_header.dart';
import 'chat_room_screen.dart';

/// Wireframe: Communities tab — class announcement + subject groups.
class ClassCommunityScreen extends StatelessWidget {
  const ClassCommunityScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.rooms,
    this.groupLabel,
    this.showHeader = true,
    this.onMenu,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final List<ChatRoomSummary> rooms;
  final String? groupLabel;
  final bool showHeader;
  final VoidCallback? onMenu;

  void _openRoom(BuildContext context, ChatRoomSummary room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          session: session,
          socket: socket,
          room: room,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcement = rooms.where((r) => r.kind == 'class_announcement').toList();
    final groups = rooms.where((r) => r.kind == 'group_chat').toList();
    final system = rooms.where((r) => r.kind == 'system_attendance' || r.kind == 'system_payment').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          StudentLandingHeader(
            onSearch: () {},
            onMenu: onMenu,
          ),
        if (showHeader)
          Container(
            color: AppColors.violet,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            alignment: Alignment.centerLeft,
            child: Text(
              groupLabel ?? 'Class Community',
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        Expanded(
          child: rooms.isEmpty
              ? const Center(child: Text('No class rooms yet', style: TextStyle(color: AppColors.textMuted)))
              : ListView(
                  children: [
                    ...announcement.map(
                      (room) => LandingSectionTile(
                        title: 'Announcements',
                        subtitle: previewForRoom(room, groupLabel: groupLabel),
                        leading: const Icon(Icons.campaign_outlined, color: AppColors.violet, size: 24),
                        onTap: () => _openRoom(context, room),
                      ),
                    ),
                    if (announcement.isNotEmpty && groups.isNotEmpty)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ...groups.map(
                      (room) => ContactChatTile(
                        room: room,
                        preview: previewForRoom(room),
                        onTap: () => _openRoom(context, room),
                      ),
                    ),
                    if (system.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          'Updates',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      ...system.map(
                        (room) => ContactChatTile(
                          room: room,
                          preview: previewForRoom(room),
                          onTap: () => _openRoom(context, room),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
