import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';

class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({
    super.key,
    required this.session,
    this.groupLabel,
  });

  final StoredSession session;
  final String? groupLabel;

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
    final username = session.user?.username;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.violet,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 16,
            left: 24,
            right: 24,
            bottom: 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              if (groupLabel != null) ...[
                const SizedBox(height: 4),
                Text(groupLabel!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
              if (username != null) ...[
                const SizedBox(height: 4),
                Text('@$username', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.school_outlined, color: AppColors.violet),
                title: const Text('Mother Care School'),
                subtitle: const Text('Student account'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: const Text('Logout', style: TextStyle(color: AppColors.error)),
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
