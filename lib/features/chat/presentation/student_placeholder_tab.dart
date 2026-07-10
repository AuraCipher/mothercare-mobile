import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';

class StudentPlaceholderTab extends StatelessWidget {
  const StudentPlaceholderTab({
    super.key,
    required this.title,
    required this.message,
    required this.session,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String message;
  final StoredSession session;
  final IconData icon;

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
    final name = session.user?.name ?? session.payload.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: AppColors.violet.withValues(alpha: 0.7)),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (title == 'Profile')
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  session.user?.username ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _logout(context),
                  child: const Text('Logout'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
