import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/presentation/login_screen.dart';

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({
    super.key,
    required this.session,
    this.unsupported = false,
  });

  final StoredSession session;
  final bool unsupported;

  Future<void> _logout(BuildContext context) async {
    await SessionStorage().clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = session.payload.role;
    final name = session.user?.name ?? session.payload.name;

    String title;
    String subtitle;

    if (unsupported) {
      title = 'Web admin only';
      subtitle = 'Role "$role" uses the web portal at ${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}';
    } else if (role == 'teacher') {
      title = 'Teacher';
      subtitle = 'Chat & class tools — Phase 1 coming next';
    } else {
      title = 'Student';
      subtitle = 'Chat landing — Phase 1 coming next';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => _logout(context),
            child: const Text('Logout'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppLogo(size: 40, borderRadius: 10, showBackground: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Welcome, $name',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  if (!unsupported) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Login successful — token and push key stored securely.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
