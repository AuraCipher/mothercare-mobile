import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/chat_room_tile.dart';
import '../../../core/widgets/universal_header.dart';
import '../widgets/room_list_icon.dart';
import 'chat_room_screen.dart';

typedef ClassCommunityRoomOpened = Future<void> Function(String roomId);

/// Drill-down: class name → Class Announcement + subject Groups.
class ClassCommunityScreen extends StatefulWidget {
  const ClassCommunityScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.groupLabel,
    required this.section,
    required this.landing,
    this.academicYearId,
    this.branchId,
    this.onRoomOpened,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final String groupLabel;
  final ChatLandingSection section;
  final ChatLandingData landing;
  final String? academicYearId;
  final String? branchId;
  final ClassCommunityRoomOpened? onRoomOpened;

  @override
  State<ClassCommunityScreen> createState() => _ClassCommunityScreenState();
}

class _ClassCommunityScreenState extends State<ClassCommunityScreen> {
  late ChatLandingSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.section;
  }

  Future<void> _markRoomReadLocally(String roomId) async {
    await widget.onRoomOpened?.call(roomId);
    if (!mounted) return;
    setState(() => _section = _sectionWithClearedRoom(roomId));
  }

  ChatLandingSection _sectionWithClearedRoom(String roomId) {
    return widget.section.copyWith(
      rooms: widget.section.rooms
          .map((r) => r.id == roomId ? r.copyWith(unreadCount: 0) : r)
          .toList(),
    );
  }

  Future<void> _openRoom(ChatRoomSummary room) async {
    await _markRoomReadLocally(room.id);
    final full = widget.landing.roomById(room.id) ?? room;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          session: widget.session,
          socket: widget.socket,
          room: full.copyWith(unreadCount: 0),
          groupLabel: widget.groupLabel,
          academicYearId: widget.academicYearId,
          branchId: widget.branchId,
        ),
      ),
    );
    if (!mounted) return;
    await _markRoomReadLocally(room.id);
  }

  @override
  Widget build(BuildContext context) {
    final announcements = classAnnouncementRooms(_section);
    final groups = classGroupRooms(_section);
    final announcement = announcements.isNotEmpty ? announcements.first : null;
    final groupCount = groups.length;
    final subtitle = groupCount > 0
        ? '$groupCount subject group${groupCount == 1 ? '' : 's'}'
        : 'Class community';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UniversalHeader(
            title: classDisplayName(widget.groupLabel),
            subtitle: subtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
              children: [
                if (announcement != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _PinnedClassAnnouncementCard(
                      room: announcement,
                      onTap: () => _openRoom(announcement),
                    ),
                  ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: const Text(
                            'Groups',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ...groups.map(
                          (room) => ChatRoomTile(
                            room: room,
                            displayName: room.name,
                            onTap: () => _openRoom(room),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (announcement == null && groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text('No class channels yet', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedClassAnnouncementCard extends StatelessWidget {
  const _PinnedClassAnnouncementCard({required this.room, required this.onTap});

  final ChatRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              colors: [
                AppColors.violet.withValues(alpha: 0.1),
                AppColors.background,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                RoomListIcon(room: room, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Announcements from teachers & admin',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
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
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: AppColors.violet.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
