import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../utils/chat_landing_layout.dart';
import '../widgets/contact_chat_tile.dart';
import '../widgets/landing_section_tile.dart';
import '../widgets/student_landing_header.dart';
import 'chat_room_screen.dart';
import 'class_community_screen.dart';

/// Student chats landing — wireframe order:
/// header → school announcement → class group → contacts.
class StudentChatLandingScreen extends StatefulWidget {
  const StudentChatLandingScreen({
    super.key,
    required this.session,
    required this.socket,
    this.groupLabel,
    this.onMenu,
    this.onOpenCommunities,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final String? groupLabel;
  final VoidCallback? onMenu;
  final VoidCallback? onOpenCommunities;

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
        ),
      ),
    ).then((_) => _load());
  }

  void _openClassCommunity(ChatLandingLayout layout) {
    if (widget.onOpenCommunities != null) {
      widget.onOpenCommunities!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClassCommunityScreen(
          session: widget.session,
          socket: widget.socket,
          rooms: layout.classCommunityRooms,
          groupLabel: widget.groupLabel,
          onMenu: widget.onMenu,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudentLandingHeader(
          onSearch: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search coming soon')),
            );
          },
          onMenu: widget.onMenu,
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

    final layout = ChatLandingLayout(_landing!);
    final school = layout.schoolAnnouncement;
    final classEntry = layout.classGroupEntry;
    final contacts = layout.contactRooms;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.violet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // school-announcement.png
          if (school != null)
            LandingSectionTile(
              title: 'Announcements',
              subtitle: previewForRoom(school),
              leading: const Icon(Icons.campaign_outlined, color: AppColors.violet, size: 24),
              leadingBackground: AppColors.violet.withValues(alpha: 0.12),
              onTap: () => _openRoom(school),
            ),
          if (school != null) const Divider(height: 1, indent: 16, endIndent: 16),

          // class-community.png
          if (classEntry != null)
            LandingSectionTile(
              title: 'Class Group',
              subtitle: previewForRoom(classEntry, groupLabel: widget.groupLabel),
              leading: const Icon(Icons.groups_rounded, color: AppColors.textPrimary, size: 24),
              leadingBackground: const Color(0xFFF0F0F5),
              onTap: () => _openClassCommunity(layout),
            ),
          if (classEntry != null && contacts.isNotEmpty)
            const Divider(height: 1, indent: 16, endIndent: 16),

          // other-contacts.png
          ...contacts.map(
            (room) => ContactChatTile(
              room: room,
              preview: previewForRoom(room),
              onTap: () => _openRoom(room),
            ),
          ),

          if (school == null && classEntry == null && contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('No chats yet', style: TextStyle(color: AppColors.textMuted))),
            ),
        ],
      ),
    );
  }
}
