import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/student_api.dart';
import '../models/student_bootstrap.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class StudentTimetablePanel extends StatefulWidget {
  const StudentTimetablePanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentTimetablePanel> createState() => _StudentTimetablePanelState();
}

class _StudentTimetablePanelState extends State<StudentTimetablePanel> {
  final _api = StudentApi();
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
      final data = await _api.fetchTimetable(
        token: widget.token,
        academicYearId: widget.bootstrap.academicYearId,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load timetable';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = (_data?['slots'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return PortalPanelScaffold(
      loading: _loading,
      offline: false,
      error: _error,
      onRetry: _load,
      child: RefreshIndicator(
        color: AppColors.violet,
        onRefresh: _load,
        child: slots.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No timetable published yet', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: slots.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final slot = slots[index];
                  final day = slot['dayOfWeek'] as int?;
                  final subject = (slot['subject'] as Map?)?['name'] as String? ?? '—';
                  final teacher = (slot['teacher'] as Map?)?['name'] as String?;
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
                        Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (day != null && day >= 1 && day <= 7) _dayNames[day - 1],
                            '${slot['startTime']} – ${slot['endTime']}',
                            ?teacher,
                          ].whereType<String>().join(' · '),
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
