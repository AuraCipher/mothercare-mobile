import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/cache_constants.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/offline_banner.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/chat_room_tile.dart';
import '../widgets/landing_header.dart';
import '../widgets/room_list_icon.dart';
import '../../../testing/e2e_keys.dart';
import 'chat_room_screen.dart';
import 'class_community_screen.dart';

enum PortalChatKind { admin, teacher }

/// Staff portal chat home — School → Teachers → Classes → Contacts.
class PortalChatLandingScreen extends StatefulWidget {
  const PortalChatLandingScreen({
    super.key,
    required this.kind,
    required this.session,
    required this.socket,
    required this.headerTitle,
    required this.academicYearId,
    this.branchId,
    this.onMenu,
  });

  final PortalChatKind kind;
  final StoredSession session;
  final ChatSocketService socket;
  final String headerTitle;
  final String academicYearId;
  final String? branchId;
  final VoidCallback? onMenu;

  @override
  State<PortalChatLandingScreen> createState() => _PortalChatLandingScreenState();
}

class _PortalChatLandingScreenState extends State<PortalChatLandingScreen> {
  final _chatApi = ChatApi();
  final _sessionStorage = SessionStorage();
  ChatLandingData? _landing;
  String? _error;
  bool _loading = true;
  bool _offline = false;

  String get _classesTitle =>
      widget.kind == PortalChatKind.teacher ? 'My Classes' : 'Class Communities';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _sessionStorage.readChatLandingCache(
      scope: widget.kind == PortalChatKind.admin
          ? ChatLandingScope.admin
          : ChatLandingScope.teacher,
      userId: widget.session.payload.id,
      branchId: widget.branchId,
    );
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
      final ChatLandingData landing;
      if (widget.kind == PortalChatKind.admin) {
        landing = await _chatApi.fetchAdminLanding(
          token: widget.session.token,
          branchId: widget.branchId!,
          academicYearId: widget.academicYearId,
        );
      } else {
        landing = await _chatApi.fetchTeacherLanding(token: widget.session.token);
      }
      await _sessionStorage.saveChatLandingCache(
        landing,
        scope: widget.kind == PortalChatKind.admin
            ? ChatLandingScope.admin
            : ChatLandingScope.teacher,
        userId: widget.session.payload.id,
        branchId: widget.branchId,
      );
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
    final branchId = widget.branchId;
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          session: widget.session,
          socket: widget.socket,
          room: full,
          academicYearId: widget.academicYearId,
          branchId: branchId,
        ),
      ),
    )
        .then((_) => _load());
  }

  void _openClassCommunity(ChatClassCommunity community) {
    final section = community.toSection();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ClassCommunityScreen(
          session: widget.session,
          socket: widget.socket,
          groupLabel: community.groupLabel,
          section: section,
          landing: _landing!,
          academicYearId: widget.academicYearId,
          branchId: widget.branchId,
        ),
      ),
    )
        .then((_) => _load());
  }

  Future<void> _openContact(ChatContactSummary contact) async {
    try {
      ChatRoomSummary room;
      if (contact.dmRoomId != null && contact.dmRoomId!.isNotEmpty) {
        room = _landing?.roomById(contact.dmRoomId!) ??
            ChatRoomSummary(
              id: contact.dmRoomId!,
              kind: 'direct_message',
              name: contact.name,
              canPost: true,
              unreadCount: 0,
            );
      } else if (widget.kind == PortalChatKind.admin) {
        room = await _chatApi.openDirectMessage(
          token: widget.session.token,
          branchId: widget.branchId!,
          academicYearId: widget.academicYearId,
          participantUserId: contact.userId,
          contactName: contact.name,
        );
      } else {
        room = await _chatApi.openTeacherDirectMessage(
          token: widget.session.token,
          participantUserId: contact.userId,
          contactName: contact.name,
        );
      }
      if (!mounted) return;
      _openRoom(room);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  ChatRoomSummary? _roomByKind(String kind) {
    for (final room in _landing?.rooms ?? []) {
      if (room.kind == kind) return room;
    }
    return null;
  }

  List<ChatClassCommunity> get _communities {
    if (_landing == null) return [];
    if (_landing!.communities.isNotEmpty) return _landing!.communities;
    final section = _landing!.sections.where((s) => s.key == 'classes').firstOrNull;
    return section?.communities ?? [];
  }

  List<ChatContactSummary> get _contacts {
    if (_landing == null) return [];
    if (_landing!.contacts.isNotEmpty) return _landing!.contacts;
    final section = _landing!.sections.where((s) => s.key == 'contacts').firstOrNull;
    return section?.contacts ?? [];
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

    final school = _roomByKind('school_announcement');
    final teachers = _roomByKind('teacher_announcement');
    final communities = _communities;
    final contacts = _contacts;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.violet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (school != null) _PinnedAnnouncementTile(room: school, onTap: () => _openRoom(school)),
          if (teachers != null)
            _PinnedAnnouncementTile(
              room: teachers,
              onTap: () => _openRoom(teachers),
              accent: AppColors.violet.withValues(alpha: 0.04),
            ),
          if (communities.isNotEmpty) ...[
            _SectionHeader(title: _classesTitle),
            ...communities.map(
              (c) => _ClassCommunityRow(community: c, onTap: () => _openClassCommunity(c)),
            ),
          ],
          if (contacts.isNotEmpty) ...[
            const _SectionHeader(title: 'Contacts'),
            ...contacts.map((c) => _ContactRow(contact: c, onTap: () => _openContact(c))),
          ],
          if (school == null && teachers == null && communities.isEmpty && contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No chat rooms yet', style: TextStyle(color: AppColors.textMuted))),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PinnedAnnouncementTile extends StatelessWidget {
  const _PinnedAnnouncementTile({
    required this.room,
    required this.onTap,
    this.accent,
  });

  final ChatRoomSummary room;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ?? AppColors.violet.withValues(alpha: 0.06),
      child: InkWell(
        key: ValueKey('${E2eKeys.chatRoomTilePrefix.value}_${room.id}'),
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

class _ClassCommunityRow extends StatelessWidget {
  const _ClassCommunityRow({required this.community, required this.onTap});

  final ChatClassCommunity community;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final groupCount = community.rooms.where((r) => r.kind == 'group_chat').length;
    final subtitle = groupCount > 0
        ? '$groupCount subject group${groupCount == 1 ? '' : 's'}'
        : 'Class community';

    return ChatRoomTile(
      room: ChatRoomSummary(
        id: community.groupId,
        kind: 'class_announcement',
        name: community.groupLabel,
        canPost: community.rooms.any((r) => r.canPost),
        unreadCount: community.unreadCount,
      ),
      displayName: community.groupLabel,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onTap});

  final ChatContactSummary contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.violet.withValues(alpha: 0.12),
        child: Text(
          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
          style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(contact.roleLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
    );
  }
}
