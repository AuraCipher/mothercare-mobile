import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/cache_constants.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../../student/models/student_bootstrap.dart';
import '../widgets/chat_room_tile.dart';
import '../../../config/app_config.dart';
import '../widgets/landing_header.dart';
import '../../../core/widgets/offline_banner.dart';
import '../widgets/room_list_icon.dart';
import '../../../testing/e2e_keys.dart';
import '../../student/presentation/student_chat_nav.dart';
import 'student_system_room_screen.dart';
import 'chat_contact_picker_screen.dart';
import 'class_community_screen.dart';
import '../widgets/new_message_bar.dart';

class StudentChatLandingScreen extends StatefulWidget {
  const StudentChatLandingScreen({
    super.key,
    required this.session,
    required this.socket,
    required     this.bootstrap,
    this.onLogout,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final StudentBootstrap bootstrap;
  final VoidCallback? onLogout;

  @override
  State<StudentChatLandingScreen> createState() => _StudentChatLandingScreenState();
}

class _StudentChatLandingScreenState extends State<StudentChatLandingScreen> {
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

  Future<void> _load({bool preferFresh = false}) async {
    if (!preferFresh) {
      final cached = await _sessionStorage.readChatLandingCache(
        scope: ChatLandingScope.student,
        userId: widget.session.payload.id,
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
    } else if (mounted) {
      setState(() => _error = null);
    }

    try {
      final landing = await _chatApi.fetchStudentLanding(token: widget.session.token);
      await _sessionStorage.saveChatLandingCache(
        landing,
        scope: ChatLandingScope.student,
        userId: widget.session.payload.id,
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

  Future<void> _clearRoomUnreadLocally(String roomId) async {
    final landing = _landing;
    if (landing == null) return;
    final updated = landing.withRoomUnreadCleared(roomId);
    setState(() => _landing = updated);
    await _sessionStorage.saveChatLandingCache(
      updated,
      scope: ChatLandingScope.student,
      userId: widget.session.payload.id,
    );
    widget.socket.markRead(roomId: roomId);
  }

  void _openRoom(ChatRoomSummary room) {
    _clearRoomUnreadLocally(room.id);
    final full = _landing?.roomById(room.id) ?? room;
    openStudentChatRoomAndWait(
      context: context,
      session: widget.session,
      socket: widget.socket,
      room: full,
      bootstrap: widget.bootstrap,
    ).then((_) => _load(preferFresh: true));
  }

  void _showMenu() {
    final bootstrap = widget.bootstrap;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(bootstrap.branchName),
              subtitle: Text(bootstrap.academicYearLabel),
            ),
            if (bootstrap.groupLabel != null)
              ListTile(
                leading: const Icon(Icons.class_outlined),
                title: Text(bootstrap.groupLabel!),
                subtitle: Text(bootstrap.userName),
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

  String get _headerTitle {
    final branch = widget.bootstrap.branchName.trim();
    if (branch.isNotEmpty) return branch;
    return AppConfig.appName;
  }

  void _openClassCommunity(ChatLandingSection section) {
    final label = classDisplayName(widget.bootstrap.groupLabel);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClassCommunityScreen(
          session: widget.session,
          socket: widget.socket,
          groupLabel: label,
          section: section,
          landing: _landing!,
          academicYearId: widget.bootstrap.academicYearId,
          onRoomOpened: _clearRoomUnreadLocally,
        ),
      ),
    ).then((_) => _load(preferFresh: true));
  }

  List<ChatLandingSection> get _visibleSections {
    final sections = _landing?.sections ?? [];
    return sections
        .where((s) => s.key != 'school' && s.key != 'class' && s.key != 'contacts' && s.key != 'system')
        .toList();
  }

  List<ChatRoomSummary> get _systemRecordRooms {
    final sections = _landing?.sections ?? [];
    final system = sections.where((s) => s.key == 'system').firstOrNull;
    final rooms = system?.rooms ?? [];
    const order = ['system_attendance', 'system_payment', 'system_result'];
    final sorted = [...rooms];
    sorted.sort((a, b) {
      final ai = order.indexOf(a.kind);
      final bi = order.indexOf(b.kind);
      return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
    });
    return sorted;
  }

  List<ChatRoomSummary> get _dmRooms {
    if (_landing == null) return [];
    final section = _landing!.sections.where((s) => s.key == 'dm').firstOrNull;
    if (section != null && section.rooms.isNotEmpty) return section.rooms;
    return _landing!.rooms.where((r) => r.kind == 'direct_message').toList();
  }

  Future<void> _openPickerContact(ContactPickerContact contact) async {
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
    } else {
      room = await _chatApi.openStudentDirectMessage(
        token: widget.session.token,
        participantUserId: contact.userId,
        contactName: contact.name,
      );
    }
    if (!mounted) return;
    _openRoom(room);
  }

  Future<void> _openContactPicker() async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatContactPickerScreen(
          currentUserId: widget.session.payload.id,
          fetchContacts: () => _chatApi.fetchStudentContacts(token: widget.session.token),
          openRoom: _openPickerContact,
        ),
      ),
    );
    if (refreshed == true) _load();
  }

  List<ChatContactSummary> get _contacts {
    if (_landing == null) return [];
    if (_landing!.contacts.isNotEmpty) return _landing!.contacts;
    final section = _landing!.sections.where((s) => s.key == 'contacts').firstOrNull;
    return section?.contacts ?? [];
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
      } else {
        room = await _chatApi.openStudentDirectMessage(
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

  ChatLandingSection? get _classSection {
    final sections = _landing?.sections ?? [];
    for (final s in sections) {
      if (s.key == 'class') return s;
    }
    return null;
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
          title: _headerTitle,
          onSearch: () {},
          onMenu: _showMenu,
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
    final classSection = _classSection;
    final sections = _visibleSections;
    final dmRooms = _dmRooms;
    final systemRecords = _systemRecordRooms;
    final hasClass = classSection != null && classSection.rooms.isNotEmpty;

    if (announcement == null && !hasClass && sections.isEmpty && dmRooms.isEmpty && systemRecords.isEmpty) {
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            color: AppColors.violet,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No chat rooms yet', style: TextStyle(color: AppColors.textMuted))),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: NewMessageFab(onTap: _openContactPicker),
          ),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: AppColors.violet,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (announcement != null)
                _SchoolAnnouncementTile(room: announcement, onTap: () => _openRoom(announcement)),
              if (hasClass)
                _ClassCommunityEntryTile(
                  title: classDisplayName(widget.bootstrap.groupLabel),
                  unread: classCommunityUnread(classSection),
                  onTap: () => _openClassCommunity(classSection),
                ),
              if (dmRooms.isNotEmpty) ...[
                _sectionHeading('Messages'),
                ...dmRooms.map(
                  (room) => ChatRoomTile(
                    room: room,
                    displayName: room.name,
                    onTap: () => _openRoom(room),
                  ),
                ),
              ],
              if (systemRecords.isNotEmpty) ...[
                _sectionHeading('School Records'),
                ...systemRecords.map(
                  (room) => StudentSystemRecordTile(
                    room: room,
                    onTap: () => _openRoom(room),
                  ),
                ),
              ],
              ...sections.expand(_buildGenericSection),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: NewMessageFab(onTap: _openContactPicker),
        ),
      ],
    );
  }

  List<Widget> _buildGenericSection(ChatLandingSection section) {
    return [
      _sectionHeading(displaySectionTitle(section, groupLabel: widget.bootstrap.groupLabel)),
      ...section.rooms.map(
        (room) => ChatRoomTile(
          room: room,
          displayName: displayRoomName(room, groupLabel: widget.bootstrap.groupLabel),
          onTap: () => _openRoom(room),
        ),
      ),
    ];
  }

  Widget _sectionHeading(String title) {
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

class _SchoolAnnouncementTile extends StatelessWidget {
  const _SchoolAnnouncementTile({required this.room, required this.onTap});

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    if (timeLabel != null)
                      Text(timeLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (room.unreadCount > 0)
                _UnreadBadge(count: room.unreadCount)
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassCommunityEntryTile extends StatelessWidget {
  const _ClassCommunityEntryTile({
    required this.title,
    required this.unread,
    required this.onTap,
  });

  final String title;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppColors.violet, width: 3),
              bottom: const BorderSide(color: AppColors.border),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_rounded, color: Color(0xFF2563EB), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'Class community',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (unread > 0) _UnreadBadge(count: unread) else const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.violet,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StudentContactRow extends StatelessWidget {
  const _StudentContactRow({required this.contact, required this.onTap});

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
