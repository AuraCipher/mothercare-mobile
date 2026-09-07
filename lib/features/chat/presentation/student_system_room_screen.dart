import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/universal_header.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../widgets/room_list_icon.dart';
import '../../student/models/student_bootstrap.dart';
import '../../student/presentation/student_attendance_panel.dart';
import '../../student/presentation/student_fees_panel.dart';
import '../../student/presentation/student_results_panel.dart';
import '../../student/presentation/student_chat_nav.dart';

/// Fixed school-record contact — full read-only dashboard + notification feed.
class StudentSystemRoomScreen extends StatefulWidget {
  const StudentSystemRoomScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.room,
    required this.bootstrap,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final ChatRoomSummary room;
  final StudentBootstrap bootstrap;

  @override
  State<StudentSystemRoomScreen> createState() => _StudentSystemRoomScreenState();
}

class _StudentSystemRoomScreenState extends State<StudentSystemRoomScreen> {
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
      case 'system_attendance':
        return StudentAttendancePanel(token: widget.session.token, bootstrap: widget.bootstrap);
      case 'system_payment':
        return StudentFeesPanel(token: widget.session.token, bootstrap: widget.bootstrap);
      case 'system_result':
        return StudentResultsPanel(token: widget.session.token, bootstrap: widget.bootstrap);
      default:
        return const Center(child: Text('Unknown record type'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = displaySystemRecordName(widget.room.kind);
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
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final message = _messages[_messages.length - 1 - index];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.title != null && message.title!.isNotEmpty)
                  Text(message.title!, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (message.displayText.isNotEmpty)
                  Text(message.displayText, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 6),
                Text(
                  message.sender.name,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class StudentSystemRecordTile extends StatelessWidget {
  const StudentSystemRecordTile({
    super.key,
    required this.room,
    required this.onTap,
  });

  final ChatRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = displaySystemRecordName(room.kind);
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
                )
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitleForKind(String kind) {
    switch (kind) {
      case 'system_attendance':
        return 'View all attendance records';
      case 'system_payment':
        return 'Fees, payments & receipts';
      case 'system_result':
        return 'Published exam results';
      default:
        return 'School record';
    }
  }
}
