import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/universal_header.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/room_list_icon.dart';
import '../../teacher/models/teacher_bootstrap.dart';
import '../../teacher/presentation/teacher_my_attendance_panel.dart';
import '../../teacher/presentation/teacher_my_payroll_panel.dart';
import '../../teacher/presentation/teacher_chat_nav.dart';

/// Teacher fixed contact — own attendance or payroll feed + records.
class TeacherSystemRoomScreen extends StatefulWidget {
  const TeacherSystemRoomScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.room,
    required this.bootstrap,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final ChatRoomSummary room;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherSystemRoomScreen> createState() => _TeacherSystemRoomScreenState();
}

class _TeacherSystemRoomScreenState extends State<TeacherSystemRoomScreen> {
  final _chatApi = ChatApi();
  List<ChatMessage> _messages = [];
  bool _loadingMessages = true;

  @override
  void initState() {
    super.initState();
    widget.socket.joinRoom(widget.room.id);
    widget.socket.markRead(roomId: widget.room.id);
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loadingMessages = true);
    try {
      final messages = await _chatApi.fetchMessages(
        token: widget.session.token,
        roomId: widget.room.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMessages = false);
    }
  }

  Widget _buildRecordPanel() {
    switch (widget.room.kind) {
      case 'system_teacher_attendance':
        return TeacherMyAttendancePanel(token: widget.session.token, bootstrap: widget.bootstrap);
      case 'system_teacher_payroll':
        return TeacherMyPayrollPanel(token: widget.session.token, bootstrap: widget.bootstrap);
      default:
        return const Center(child: Text('Unknown record type'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = displayTeacherSystemRecordName(widget.room.kind);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: title,
              subtitle: widget.bootstrap.academicYearLabel,
              showBack: true,
            ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Material(
                      color: AppColors.surface,
                      child: const TabBar(
                        labelColor: AppColors.violet,
                        unselectedLabelColor: AppColors.textMuted,
                        indicatorColor: AppColors.violet,
                        tabs: [
                          Tab(text: 'All records'),
                          Tab(text: 'Updates'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRecordPanel(),
                          _buildUpdatesTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesTab() {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }
    if (_messages.isEmpty) {
      return RefreshIndicator(
        color: AppColors.violet,
        onRefresh: _loadMessages,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(child: Text('No updates yet', style: TextStyle(color: AppColors.textMuted))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.violet,
      onRefresh: _loadMessages,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final msg = _messages[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.title != null && msg.title!.isNotEmpty)
                  Text(msg.title!, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (msg.content != null && msg.content!.isNotEmpty) ...[
                  if (msg.title != null && msg.title!.isNotEmpty) const SizedBox(height: 6),
                  Text(msg.content!, style: const TextStyle(color: AppColors.textPrimary)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class TeacherSystemRecordTile extends StatelessWidget {
  const TeacherSystemRecordTile({
    super.key,
    required this.room,
    required this.onTap,
  });

  final ChatRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = displayTeacherSystemRecordName(room.kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              RoomListIcon(room: room, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      _subtitleForKind(room.kind),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleForKind(String kind) {
    switch (kind) {
      case 'system_teacher_attendance':
        return 'Your absent, late, and leave updates';
      case 'system_teacher_payroll':
        return 'Salary and payroll messages';
      default:
        return 'School updates';
    }
  }
}
