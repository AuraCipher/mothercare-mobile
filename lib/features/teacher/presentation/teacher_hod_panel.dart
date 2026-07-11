import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/teacher_api.dart';
import '../models/teacher_bootstrap.dart';

class TeacherHodPanel extends StatefulWidget {
  const TeacherHodPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherHodPanel> createState() => _TeacherHodPanelState();
}

class _TeacherHodPanelState extends State<TeacherHodPanel> {
  final _api = TeacherApi();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchHodDepartment(token: widget.token, bootstrap: widget.bootstrap);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load department overview';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = (_data?['subjects'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return PortalPanelScaffold(
      loading: _loading,
      offline: false,
      error: _error,
      onRetry: _load,
      child: RefreshIndicator(
        color: AppColors.violet,
        onRefresh: _load,
        child: subjects.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No HOD department subjects', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: subjects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final subject = subjects[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subject['name'] as String? ?? 'Subject', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${subject['teacherCount'] ?? 0} teachers · ${subject['examSubjectCount'] ?? 0} exam sheets',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
