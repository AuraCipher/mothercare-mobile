import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/staff_api.dart';
import '../models/staff_bootstrap.dart';

class StaffProfileTab extends StatefulWidget {
  const StaffProfileTab({
    super.key,
    required this.token,
    required this.bootstrap,
    this.onLogout,
  });

  final String token;
  final StaffBootstrap bootstrap;
  final VoidCallback? onLogout;

  @override
  State<StaffProfileTab> createState() => _StaffProfileTabState();
}

class _StaffProfileTabState extends State<StaffProfileTab> {
  final _api = StaffApi();
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
      final profile = await _api.fetchProfile(token: widget.token, bootstrap: widget.bootstrap);
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

    final name = _profile?['name'] as String? ?? widget.bootstrap.userName;
    final email = _profile?['email'] as String?;
    final username = _profile?['username'] as String?;
    final phone = _profile?['phone'] as String?;
    final branch = (_profile?['branch'] as Map?)?['name'] as String? ?? widget.bootstrap.branchName;
    final profile = _profile?['profile'] as Map<String, dynamic>?;
    final workRole = profile?['workRole'] as String?;
    final employeeId = profile?['employeeId'] as String?;
    final memberSince = _profile?['memberSince'] as String?;

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
                          widget.bootstrap.roleLabel,
                          style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _row('Branch', branch),
              _row('Academic year', widget.bootstrap.academicYearLabel),
              if (workRole != null && workRole.isNotEmpty) _row('Role', workRole),
              if (employeeId != null && employeeId.isNotEmpty) _row('Employee ID', employeeId),
              if (phone != null && phone.isNotEmpty) _row('Phone', phone),
              if (email != null && email.isNotEmpty) _row('Email', email),
              if (username != null && username.isNotEmpty) _row('Username', username),
              if (memberSince != null)
                _row('Member since', DateFormat('d MMM yyyy').format(DateTime.parse(memberSince).toLocal())),
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
