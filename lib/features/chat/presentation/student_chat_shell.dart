import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';
import '../../student/data/student_api.dart';
import '../data/chat_socket_service.dart';
import '../../../core/widgets/universal_header.dart';
import '../widgets/student_bottom_nav.dart';
import 'student_chat_landing_screen.dart';
import 'student_placeholder_tab.dart';

/// Student home — bootstrap, socket, bottom nav, chat landing.
class StudentChatShell extends StatefulWidget {
  const StudentChatShell({super.key, required this.session});

  final StoredSession session;

  @override
  State<StudentChatShell> createState() => _StudentChatShellState();
}

class _StudentChatShellState extends State<StudentChatShell> {
  final _studentApi = StudentApi();
  final _socket = ChatSocketService();
  String? _academicYearId;
  String? _groupLabel;
  String? _error;
  bool _loading = true;
  StudentNavTab _tab = StudentNavTab.chats;

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
      if (!mounted) return;
      setState(() {
        _academicYearId = data.academicYearId;
        _groupLabel = data.groupLabel;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.violet)),
      );
    }

    if (_error != null || _academicYearId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mother Care')),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(top: false, bottom: false, child: _buildTabBody()),
      bottomNavigationBar: StudentBottomNav(
        current: _tab,
        onChanged: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case StudentNavTab.chats:
        return StudentChatLandingScreen(
          session: widget.session,
          socket: _socket,
          academicYearId: _academicYearId!,
          groupLabel: _groupLabel,
          onLogout: _logout,
        );
      case StudentNavTab.academics:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const UniversalHeader(title: 'Academics'),
            Expanded(
              child: StudentPlaceholderTab(
                title: 'Academics',
                message: 'Fees, attendance, results, and timetable — coming in Phase 2.',
                session: widget.session,
                icon: Icons.menu_book_outlined,
              ),
            ),
          ],
        );
      case StudentNavTab.profile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const UniversalHeader(title: 'Profile'),
            Expanded(
              child: StudentPlaceholderTab(
                title: 'Profile',
                message: 'Your school profile and settings.',
                session: widget.session,
                icon: Icons.person_outline_rounded,
              ),
            ),
          ],
        );
    }
  }
}
