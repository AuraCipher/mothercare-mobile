import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/presentation/login_screen.dart';
import '../../student/data/student_api.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../utils/chat_landing_layout.dart';
import '../widgets/student_bottom_nav.dart';
import '../../../core/theme/app_theme.dart';
import 'class_community_screen.dart';
import 'student_chat_landing_screen.dart';
import 'student_profile_screen.dart';

/// Student home — bootstrap, socket, bottom nav, landing structure.
class StudentChatShell extends StatefulWidget {
  const StudentChatShell({super.key, required this.session});

  final StoredSession session;

  @override
  State<StudentChatShell> createState() => _StudentChatShellState();
}

class _StudentChatShellState extends State<StudentChatShell> {
  final _studentApi = StudentApi();
  final _chatApi = ChatApi();
  final _socket = ChatSocketService();
  String? _academicYearId;
  String? _groupLabel;
  String? _error;
  bool _loading = true;
  StudentNavTab _tab = StudentNavTab.chats;
  ChatLandingData? _landing;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _studentApi.fetchBootstrap(token: widget.session.token);
      if (data.academicYearId.isEmpty) {
        throw ApiException('No active academic year');
      }
      await SessionStorage().saveAcademicYearId(data.academicYearId);
      _socket.connect(
        token: widget.session.token,
        academicYearId: data.academicYearId,
      );
      final landing = await _chatApi.fetchStudentLanding(token: widget.session.token);
      if (!mounted) return;
      setState(() {
        _academicYearId = data.academicYearId;
        _groupLabel = data.groupLabel;
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
        _error = 'Could not start chat. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await SessionStorage().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(ctx);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _academicYearId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Setup failed', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _bootstrap, child: const Text('Retry')),
                TextButton(onPressed: _logout, child: const Text('Logout')),
              ],
            ),
          ),
        ),
      );
    }

    final layout = _landing != null ? ChatLandingLayout(_landing!) : null;
    final unread = layout?.totalUnread ?? 0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildTabBody(layout),
      bottomNavigationBar: StudentBottomNav(
        current: _tab,
        chatsBadge: unread,
        onChanged: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  Widget _buildTabBody(ChatLandingLayout? layout) {
    switch (_tab) {
      case StudentNavTab.chats:
        return StudentChatLandingScreen(
          session: widget.session,
          socket: _socket,
          groupLabel: _groupLabel,
          onMenu: _showMenu,
          onOpenCommunities: () => setState(() => _tab = StudentNavTab.communities),
        );
      case StudentNavTab.communities:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.violet,
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 16,
                right: 16,
                bottom: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Communities',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  if (_groupLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(_groupLabel!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ClassCommunityScreen(
                session: widget.session,
                socket: _socket,
                rooms: layout?.classCommunityRooms ?? [],
                groupLabel: _groupLabel,
                showHeader: false,
                onMenu: _showMenu,
              ),
            ),
          ],
        );
      case StudentNavTab.profile:
        return StudentProfileScreen(
          session: widget.session,
          groupLabel: _groupLabel,
        );
    }
  }
}
