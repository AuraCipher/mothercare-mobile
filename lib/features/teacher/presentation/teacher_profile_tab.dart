import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/teacher_api.dart';
import '../models/teacher_bootstrap.dart';

class TeacherProfileTab extends StatefulWidget {
  const TeacherProfileTab({
    super.key,
    required this.token,
    required this.bootstrap,
    this.onLogout,
  });

  final String token;
  final TeacherBootstrap bootstrap;
  final VoidCallback? onLogout;

  @override
  State<TeacherProfileTab> createState() => _TeacherProfileTabState();
}

class _TeacherProfileTabState extends State<TeacherProfileTab> {
  final _api = TeacherApi();
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await _api.fetchProfile(token: widget.token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }

    final user = _profile?['user'] as Map<String, dynamic>? ?? {};
    final name = user['name'] as String? ?? widget.bootstrap.userName;
    final email = user['email'] as String?;
    final username = user['username'] as String?;
    final employeeId = _profile?['employeeId'] as String?;
    final qualification = _profile?['qualification'] as String?;
    final phone = _profile?['phone'] as String?;
    final joining = _profile?['joiningDate'] as String?;

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
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                        Text(
                          widget.bootstrap.isHod ? 'Teacher · HOD' : 'Teacher',
                          style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _row('Branch', widget.bootstrap.branchName),
              _row('Academic year', widget.bootstrap.academicYearLabel),
              if (employeeId != null && employeeId.isNotEmpty) _row('Employee ID', employeeId),
              if (qualification != null && qualification.isNotEmpty) _row('Qualification', qualification),
              if (phone != null && phone.isNotEmpty) _row('Phone', phone),
              if (email != null && email.isNotEmpty) _row('Email', email),
              if (username != null && username.isNotEmpty) _row('Username', username),
              if (joining != null)
                _row('Joining date', DateFormat('d MMM yyyy').format(DateTime.parse(joining).toLocal())),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (widget.onLogout != null)
          OutlinedButton(onPressed: widget.onLogout, child: const Text('Logout')),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}
