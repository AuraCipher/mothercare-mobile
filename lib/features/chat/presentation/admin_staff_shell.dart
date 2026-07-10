import 'package:flutter/material.dart';

import '../../../core/push/chat_push_nav.dart';
import '../../../core/push/chat_push_service.dart';
import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/universal_header.dart';
import '../../auth/presentation/login_screen.dart';
import '../../staff/data/staff_api.dart';
import '../../staff/models/staff_bootstrap.dart';
import '../data/chat_socket_service.dart';
import '../widgets/portal_bottom_nav.dart';
import 'portal_profile_tab.dart';
import 'portal_chat_landing_screen.dart';

class AdminStaffShell extends StatefulWidget {
  const AdminStaffShell({super.key, required this.session});

  final StoredSession session;

  @override
  State<AdminStaffShell> createState() => _AdminStaffShellState();
}

class _AdminStaffShellState extends State<AdminStaffShell> {
  final _staffApi = StaffApi();
  final _sessionStorage = SessionStorage();
  final _socket = ChatSocketService();
  StaffBootstrap? _bootstrap;
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
    ChatPushService.instance.setRoomTapHandler((roomId, roomName) {
      if (!mounted) return;
      final bootstrap = _bootstrap;
      if (bootstrap == null) return;
      setState(() => _tab = PortalNavTab.chats);
      openChatRoomFromPush(
        context: context,
        session: widget.session,
        socket: _socket,
        roomId: roomId,
        roomName: roomName,
        academicYearId: bootstrap.academicYearId,
        branchId: bootstrap.branchId,
      );
    });
    ChatPushService.instance.bindSession(widget.session.token);
  }

  void _applyBootstrap(StaffBootstrap data) {
    _socket.connect(token: widget.session.token, academicYearId: data.academicYearId);
    setState(() {
      _bootstrap = data;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _loadBootstrap() async {
    final cached = await _sessionStorage.readStaffBootstrapCache();
    if (cached != null && cached.academicYearId.isNotEmpty && mounted) {
      _applyBootstrap(cached);
    } else if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _staffApi.fetchBootstrap(
        token: widget.session.token,
        userName: widget.session.user?.name ?? widget.session.payload.name,
        role: widget.session.payload.role,
      );
      await _sessionStorage.saveStaffBootstrapCache(data);
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
          _error = 'Could not load admin portal. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await ChatPushService.instance.unbindSession();
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
              leading: const Icon(Icons.apartment_rounded),
              title: Text(bootstrap.branchName),
              subtitle: Text(bootstrap.roleLabel),
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
        workspaceLabel: 'Campus',
        workspaceIcon: Icons.apartment_outlined,
        workspaceSelectedIcon: Icons.apartment_rounded,
      ),
    );
  }

  Widget _buildTabBody() {
    final bootstrap = _bootstrap!;
    switch (_tab) {
      case PortalNavTab.chats:
        return PortalChatLandingScreen(
          kind: PortalChatKind.admin,
          session: widget.session,
          socket: _socket,
          headerTitle: bootstrap.branchName,
          branchId: bootstrap.branchId,
          academicYearId: bootstrap.academicYearId,
          onMenu: _showMenu,
        );
      case PortalNavTab.workspace:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(
              title: bootstrap.branchName,
              subtitle: bootstrap.roleLabel,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _CampusCard(
                    icon: Icons.people_outline_rounded,
                    title: 'Staff & students',
                    subtitle: 'Roster, admissions, and staff tools — Phase 2',
                  ),
                  const SizedBox(height: 12),
                  _CampusCard(
                    icon: Icons.campaign_outlined,
                    title: 'Announcements',
                    subtitle: 'School-wide posts from admin — Phase 2',
                  ),
                  const SizedBox(height: 12),
                  _CampusCard(
                    icon: Icons.payments_outlined,
                    title: 'Fees & finance',
                    subtitle: 'Collections and reports — Phase 2',
                  ),
                ],
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
              subtitle: bootstrap.roleLabel,
            ),
            Expanded(
              child: PortalProfileTab(
                userName: bootstrap.userName,
                branchName: bootstrap.branchName,
                academicYearLabel: bootstrap.academicYearLabel,
                roleLabel: bootstrap.roleLabel,
                onLogout: _logout,
              ),
            ),
          ],
        );
    }
  }
}

class _CampusCard extends StatelessWidget {
  const _CampusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.violet),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
