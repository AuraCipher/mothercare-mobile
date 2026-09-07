import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../student/data/student_api.dart';
import '../../student/models/student_bootstrap.dart';

class StudentProfileTab extends StatefulWidget {
  const StudentProfileTab({
    super.key,
    required this.token,
    required this.bootstrap,
    this.onLogout,
  });

  final String token;
  final StudentBootstrap bootstrap;
  final VoidCallback? onLogout;

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
  final _api = StudentApi();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final profile = await _api.fetchProfile(token: widget.token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load profile. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.grey.shade500, size: 40),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.grey.shade400), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final p = _profile;
    final name = p?['name'] as String? ?? widget.bootstrap.userName;
    final roll = p?['rollNumber'] as String? ?? widget.bootstrap.rollNumber;
    final group = (p?['group'] as Map?)?['label'] as String? ?? widget.bootstrap.groupLabel;
    final email = p?['email'] as String?;
    final username = p?['username'] as String?;
    final admission = p?['admissionDate'] as String?;
    final ayLabel = (p?['academicYear'] as Map?)?['label'] as String? ?? widget.bootstrap.academicYearLabel;

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
                        const SizedBox(height: 4),
                        const Text('Student', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (roll != null) _row('Roll number', roll),
              if (group != null) _row('Class', group),
              _row('Branch', widget.bootstrap.branchName),
              _row('Academic year', ayLabel),
              if (email != null && email.isNotEmpty) _row('Email', email),
              if (username != null && username.isNotEmpty) _row('Username', username),
              if (admission != null)
                _row('Admission', DateFormat('d MMM yyyy').format(DateTime.parse(admission).toLocal())),
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
