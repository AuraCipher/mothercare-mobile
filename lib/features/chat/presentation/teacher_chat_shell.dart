import 'package:flutter/material.dart';

import '../models/chat_models.dart';
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
import '../../../core/widgets/universal_header.dart';
import '../../auth/presentation/login_screen.dart';
import '../../teacher/presentation/teacher_chat_nav.dart';
import '../../teacher/data/teacher_api.dart';
import '../../teacher/models/teacher_bootstrap.dart';
import '../data/chat_socket_service.dart';
import '../widgets/portal_bottom_nav.dart';
import '../../teacher/presentation/teacher_workspace_tab.dart';
import '../../teacher/presentation/teacher_profile_tab.dart';
import 'portal_chat_landing_screen.dart';

class TeacherChatShell extends StatefulWidget {
  const TeacherChatShell({super.key, required this.session});

  final StoredSession session;

  @override
  State<TeacherChatShell> createState() => _TeacherChatShellState();
}

class _TeacherChatShellState extends State<TeacherChatShell> {
  final _teacherApi = TeacherApi();
  final _sessionStorage = SessionStorage();
  final _socket = ChatSocketService();
  TeacherBootstrap? _bootstrap;
  String? _error;
  bool _loading = true;
  PortalNavTab _tab = PortalNavTab.chats;

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
      setState(() => _tab = PortalNavTab.chats);
      // M9: resolve the authoritative kind from cached landing data so
      // teacher system feeds open TeacherSystemRoomScreen (previously every
      // push fell back to the generic room screen).
      String kind = '';
      try {
        final landing = await _sessionStorage.readChatLandingCache(
          scope: ChatLandingScope.teacher,
          userId: widget.session.payload.id,
          branchId: bootstrap.branchId,
        );
        if (landing != null) kind = findCachedPushRoom(landing, roomId)?.kind ?? '';
      } catch (_) {}
      if (!mounted) return;
      openTeacherChatRoom(
        context: context,
        session: widget.session,
        socket: _socket,
        room: ChatRoomSummary(
          id: roomId,
          kind: kind,
          name: roomName,
          canPost: false,
          unreadCount: 0,
        ),
        bootstrap: bootstrap,
      );
    });
    ChatPushService.instance.bindSession(widget.session.token);
  }

  void _applyBootstrap(TeacherBootstrap data) {
    _socket.connect(token: widget.session.token, academicYearId: data.academicYearId);
    setState(() {
      _bootstrap = data;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _loadBootstrap() async {
    final cached = await _sessionStorage.readTeacherBootstrapCache();
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
      final data = await _teacherApi.fetchBootstrap(token: widget.session.token);
      await _sessionStorage.saveAcademicYearId(data.academicYearId);
      await _sessionStorage.saveTeacherBootstrapCache(data);
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
          _error = 'Could not load teacher portal. Check your connection.';
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

  void _showMenu() {
    final bootstrap = _bootstrap;
    if (bootstrap == null) return;
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
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(bootstrap.userName),
              subtitle: Text('${bootstrap.assignmentCount} assignments'),
            ),
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
      bottomNavigationBar: PortalBottomNav(
        current: _tab,
        onChanged: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  Widget _buildTabBody() {
    final bootstrap = _bootstrap!;
    switch (_tab) {
      case PortalNavTab.chats:
        return PortalChatLandingScreen(
          kind: PortalChatKind.teacher,
          session: widget.session,
          socket: _socket,
          headerTitle: bootstrap.branchName,
          branchId: bootstrap.branchId,
          academicYearId: bootstrap.academicYearId,
          teacherBootstrap: bootstrap,
          onMenu: _showMenu,
        );
      case PortalNavTab.workspace:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: 'Workspace',
              subtitle: bootstrap.academicYearLabel,
            ),
            Expanded(
              child: TeacherWorkspaceTab(
                token: widget.session.token,
                bootstrap: bootstrap,
              ),
            ),
          ],
        );
      case PortalNavTab.profile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: bootstrap.userName,
              subtitle: bootstrap.isHod ? 'Head of Department' : 'Teacher',
            ),
            Expanded(
              child: TeacherProfileTab(
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
