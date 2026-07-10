import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/chat_room_tile.dart';
import '../widgets/room_list_icon.dart';
import '../widgets/landing_header.dart';
import 'chat_room_screen.dart';

class StudentChatLandingScreen extends StatefulWidget {
  const StudentChatLandingScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.academicYearId,
    this.groupLabel,
    this.onLogout,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final String academicYearId;
  final String? groupLabel;
  final VoidCallback? onLogout;

  @override
  State<StudentChatLandingScreen> createState() => _StudentChatLandingScreenState();
}

class _StudentChatLandingScreenState extends State<StudentChatLandingScreen> {
  final _chatApi = ChatApi();
  ChatLandingData? _landing;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final landing = await _chatApi.fetchStudentLanding(token: widget.session.token);
      if (!mounted) return;
      setState(() {
        _landing = landing;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load chat. Pull to refresh.';
        _loading = false;
      });
    }
  }

  void _openRoom(ChatRoomSummary room) {
    final full = _landing?.roomById(room.id) ?? room;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          session: widget.session,
          socket: widget.socket,
          room: full,
          groupLabel: widget.groupLabel,
        ),
      ),
    ).then((_) => _load());
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.groupLabel != null)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(widget.groupLabel!),
                subtitle: const Text('Your class'),
              ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onLogout?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<ChatLandingSection> get _visibleSections {
    final sections = _landing?.sections ?? [];
    return sections.where((s) => s.key != 'school').toList();
  }

  ChatRoomSummary? get _announcementRoom {
    final rooms = _landing?.rooms ?? [];
    for (final room in rooms) {
      if (room.kind == 'school_announcement') return room;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LandingHeader(
          onSearch: () {},
          onMenu: _showMenu,
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _landing == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }

    if (_error != null && _landing == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final announcement = _announcementRoom;
    final sections = _visibleSections;

    if (announcement == null && sections.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.violet,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No chat rooms yet', style: TextStyle(color: AppColors.textMuted))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.violet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (announcement != null) _AnnouncementPinnedTile(room: announcement, onTap: () => _openRoom(announcement)),
          ...sections.expand((section) => [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    displaySectionTitle(section, groupLabel: widget.groupLabel),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                ...section.rooms.map(
                  (room) => ChatRoomTile(
                    room: room,
                    displayName: displayRoomName(room, groupLabel: widget.groupLabel),
                    onTap: () => _openRoom(room),
                  ),
                ),
              ]),
        ],
      ),
    );
  }
}

class _AnnouncementPinnedTile extends StatelessWidget {
  const _AnnouncementPinnedTile({required this.room, required this.onTap});

  final ChatRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeLabel = room.lastMessageAt != null
        ? DateFormat('MMM d, h:mm a').format(room.lastMessageAt!.toLocal())
        : null;

    return Material(
      color: AppColors.violet.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: roomIconStyle(room).background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  roomIconStyle(room).icon,
                  color: roomIconStyle(room).foreground,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Announcement',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    if (timeLabel != null)
                      Text(timeLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
