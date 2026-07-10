import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../student/models/student_bootstrap.dart';

class StudentPlaceholderTab extends StatelessWidget {
  const StudentPlaceholderTab({
    super.key,
    required this.bootstrap,
    required this.message,
    this.icon = Icons.construction_outlined,
    this.showLogout = false,
    this.onLogout,
  });

  final StudentBootstrap bootstrap;
  final String message;
  final IconData icon;
  final bool showLogout;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
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
                    bootstrap.academicYearLabel,
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
        if (showLogout)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bootstrap.groupLabel != null) ...[
                  Text(
                    bootstrap.groupLabel!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                ],
                if (bootstrap.rollNumber != null)
                  Text(
                    'Roll ${bootstrap.rollNumber}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onLogout,
                  child: const Text('Logout'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
