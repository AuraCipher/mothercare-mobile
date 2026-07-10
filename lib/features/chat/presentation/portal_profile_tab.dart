import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class PortalProfileTab extends StatelessWidget {
  const PortalProfileTab({
    super.key,
    required this.userName,
    required this.branchName,
    required this.academicYearLabel,
    required this.roleLabel,
    this.extraLines = const [],
    this.onLogout,
  });

  final String userName;
  final String branchName;
  final String academicYearLabel;
  final String roleLabel;
  final List<String> extraLines;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
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
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.violet.withValues(alpha: 0.12),
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(roleLabel, style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Branch', value: branchName),
              _InfoRow(label: 'Academic year', value: academicYearLabel),
              for (final line in extraLines) _InfoRow(label: 'Details', value: line),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onLogout,
          child: const Text('Logout'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}
