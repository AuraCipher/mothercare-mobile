import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/offline_banner.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/chat_room_tile.dart';
import '../widgets/landing_header.dart';
import '../widgets/room_list_icon.dart';
import 'chat_room_screen.dart';

/// Staff chat home — teachers and branch admins.
class StaffChatLandingScreen extends StatefulWidget {
  const StaffChatLandingScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.headerTitle,
    required this.academicYearId,
    this.onMenu,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final String headerTitle;
  final String academicYearId;
  final VoidCallback? onMenu;

  @override
  State<StaffChatLandingScreen> createState() => _StaffChatLandingScreenState();
}

class _StaffChatLandingScreenState extends State<StaffChatLandingScreen> {
  final _chatApi = ChatApi();
  final _sessionStorage = SessionStorage();
  ChatLandingData? _landing;
  String? _error;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _sessionStorage.readChatLandingCache();
    if (cached != null && mounted) {
      setState(() {
        _landing = cached;
        _loading = false;
        _error = null;
      });
    } else if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final landing = await _chatApi.fetchStaffLanding(
        token: widget.session.token,
        academicYearId: widget.academicYearId,
      );
      await _sessionStorage.saveChatLandingCache(landing);
      if (!mounted) return;
      setState(() {
        _landing = landing;
        _loading = false;
        _offline = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_landing != null) {
        setState(() => _offline = true);
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_landing != null) {
        setState(() => _offline = true);
      } else {
        setState(() {
          _error = 'Could not load chat. Pull to refresh.';
          _loading = false;
        });
      }
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
        ),
      ),
    ).then((_) => _load());
  }

  ChatRoomSummary? get _announcementRoom {
    for (final room in _landing?.rooms ?? []) {
      if (room.kind == 'school_announcement') return room;
    }
    return null;
  }

  List<ChatLandingSection> get _channelSections {
    return (_landing?.sections ?? []).where((s) => s.key != 'school').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LandingHeader(
          title: widget.headerTitle,
          onSearch: () {},
          onMenu: widget.onMenu,
        ),
        if (_offline) const OfflineBanner(),
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
              const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final announcement = _announcementRoom;
    final sections = _channelSections;

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
          if (announcement != null) _AnnouncementTile(room: announcement, onTap: () => _openRoom(announcement)),
          ...sections.expand(_buildSection),
        ],
      ),
    );
  }

  List<Widget> _buildSection(ChatLandingSection section) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          section.title,
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
          displayName: room.name,
          onTap: () => _openRoom(room),
        ),
      ),
    ];
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.room, required this.onTap});

  final ChatRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              RoomListIcon(room: room, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  room.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
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
