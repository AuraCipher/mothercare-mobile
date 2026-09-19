import 'package:flutter/material.dart';

import '../../student/presentation/student_chat_nav.dart';
import '../../../core/push/chat_push_service.dart';
import '../../../core/push/push_room_resolve.dart';
import '../../../core/storage/cache_constants.dart';
import '../../../core/storage/chat_message_cache_store.dart';
import '../../../core/storage/pending_outgoing_store.dart';
import '../data/chat_upload_pool.dart';
import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';
import '../../student/data/student_api.dart';
import '../../student/models/student_bootstrap.dart';
import '../data/chat_socket_service.dart';
import '../widgets/student_bottom_nav.dart';
import '../../../core/widgets/universal_header.dart';
import '../../student/presentation/student_academics_tab.dart';
import 'student_chat_landing_screen.dart';
import '../../student/presentation/student_profile_tab.dart';

/// Student home — bootstrap, socket, bottom nav, chat landing.
class StudentChatShell extends StatefulWidget {
  const StudentChatShell({super.key, required this.session});

  final StoredSession session;

  @override
  State<StudentChatShell> createState() => _StudentChatShellState();
}

class _StudentChatShellState extends State<StudentChatShell> {
  final _studentApi = StudentApi();
  final _sessionStorage = SessionStorage();
  final _socket = ChatSocketService();
  StudentBootstrap? _bootstrap;
  String? _error;
  bool _loading = true;
  StudentNavTab _tab = StudentNavTab.chats;

  @override
  void initState() {
    super.initState();
    _bindPush();
    _loadBootstrap();
  }

  @override
  void dispose() {
    ChatPushService.instance.setRoomTapHandler(null);
    _socket.dispose();
    super.dispose();
  }

  void _bindPush() {
    ChatPushService.instance.setRoomTapHandler((roomId, roomName) async {
      if (!mounted) return;
      final bootstrap = _bootstrap;
      if (bootstrap == null) return;
      setState(() => _tab = StudentNavTab.chats);
      // M9: resolve the authoritative kind from cached landing data first;
      // the name heuristic inside openStudentChatRoomFromPush is fallback.
      String? kind;
      try {
        final landing = await _sessionStorage.readChatLandingCache(
          scope: ChatLandingScope.student,
          userId: widget.session.payload.id,
        );
        if (landing != null) kind = findCachedPushRoom(landing, roomId)?.kind;
      } catch (_) {}
      if (!mounted) return;
      openStudentChatRoomFromPush(
        context: context,
        session: widget.session,
        socket: _socket,
        roomId: roomId,
        roomName: roomName,
        bootstrap: bootstrap,
        roomKind: kind,
      );
    });
    ChatPushService.instance.bindSession(widget.session.token);
  }

  void _applyBootstrap(StudentBootstrap data) {
    _socket.connect(
      token: widget.session.token,
      academicYearId: data.academicYearId,
    );
    setState(() {
      _bootstrap = data;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _loadBootstrap() async {
    final cached = await _sessionStorage.readBootstrapCache();
    if (cached != null && cached.academicYearId.isNotEmpty && mounted) {
      await _sessionStorage.saveAcademicYearId(cached.academicYearId);
      _applyBootstrap(cached);
    } else if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _studentApi.fetchBootstrap(token: widget.session.token);
      if (data.academicYearId.isEmpty) {
        throw ApiException('No active academic year');
      }
      await _sessionStorage.saveAcademicYearId(data.academicYearId);
      await _sessionStorage.saveBootstrapCache(data);
      if (!mounted) return;
      _applyBootstrap(data);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_bootstrap == null) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_bootstrap == null) {
        setState(() {
          _error = 'Could not start chat. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await ChatPushService.instance.unbindSession();
    await ChatMessageCacheStore.instance.clearUser(widget.session.payload.id);
    await PendingOutgoingStore.instance.clearUser(widget.session.payload.id);
    await ChatUploadPool.releaseAll();
    await _sessionStorage.clear();
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

    if (_error != null || _bootstrap == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppConfig.appName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(_error ?? 'Setup failed', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _loadBootstrap, child: const Text('Retry')),
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
    final bootstrap = _bootstrap!;
    switch (_tab) {
      case StudentNavTab.chats:
        return StudentChatLandingScreen(
          session: widget.session,
          socket: _socket,
          bootstrap: bootstrap,
          onLogout: _logout,
        );
      case StudentNavTab.academics:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: bootstrap.academicYearLabel,
              subtitle: bootstrap.branchName,
            ),
            Expanded(
              child: StudentAcademicsTab(
                token: widget.session.token,
                bootstrap: bootstrap,
              ),
            ),
          ],
        );
      case StudentNavTab.profile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: bootstrap.userName,
              subtitle: bootstrap.groupLabel,
            ),
            Expanded(
              child: StudentProfileTab(
                token: widget.session.token,
                bootstrap: bootstrap,
                onLogout: _logout,
              ),
            ),
          ],
        );
    }
  }
}
