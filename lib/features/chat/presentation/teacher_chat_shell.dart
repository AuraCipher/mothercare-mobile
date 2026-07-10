import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/universal_header.dart';
import '../../auth/presentation/login_screen.dart';
import '../../teacher/data/teacher_api.dart';
import '../../teacher/models/teacher_bootstrap.dart';
import '../data/chat_socket_service.dart';
import '../widgets/portal_bottom_nav.dart';
import 'portal_profile_tab.dart';
import 'staff_chat_landing_screen.dart';
import 'teacher_classes_tab.dart';

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
    _loadBootstrap();
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
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
        return StaffChatLandingScreen(
          session: widget.session,
          socket: _socket,
          headerTitle: bootstrap.branchName,
          academicYearId: bootstrap.academicYearId,
          onMenu: _showMenu,
        );
      case PortalNavTab.workspace:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: 'My Classes',
              subtitle: bootstrap.academicYearLabel,
            ),
            Expanded(child: TeacherClassesTab(bootstrap: bootstrap)),
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
              child: PortalProfileTab(
                userName: bootstrap.userName,
                branchName: bootstrap.branchName,
                academicYearLabel: bootstrap.academicYearLabel,
                roleLabel: bootstrap.isHod ? 'Teacher · HOD' : 'Teacher',
                extraLines: [
                  if (bootstrap.portalAccess != 'FULL') 'Portal access: ${bootstrap.portalAccess}',
                ],
                onLogout: _logout,
              ),
            ),
          ],
        );
    }
  }
}
