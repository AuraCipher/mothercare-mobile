import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/teacher_api.dart';
import '../models/teacher_bootstrap.dart';

class TeacherMyAttendancePanel extends StatefulWidget {
  const TeacherMyAttendancePanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherMyAttendancePanel> createState() => _TeacherMyAttendancePanelState();
}

class _TeacherMyAttendancePanelState extends State<TeacherMyAttendancePanel> {
  final _api = TeacherApi();
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await _api.fetchMyAttendance(token: widget.token, bootstrap: widget.bootstrap);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load attendance. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPanelScaffold(
      loading: _loading,
      offline: false,
      error: _error,
      onRetry: _load,
      child: RefreshIndicator(
        color: AppColors.violet,
        onRefresh: _load,
        child: _rows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No attendance records yet', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final date = DateTime.tryParse(row['date']?.toString() ?? '');
                  final status = (row['status'] as String? ?? '').toLowerCase();
                  final note = row['note'] as String?;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                date != null ? DateFormat('EEE, d MMM yyyy').format(date.toLocal()) : '—',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (note != null && note.isNotEmpty)
                                Text(note, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        _StatusChip(status: status),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.border;
    Color fg = AppColors.textMuted;
    switch (status) {
      case 'present':
        bg = const Color(0xFFE6F7F1);
        fg = const Color(0xFF059669);
      case 'absent':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
      case 'late':
        bg = const Color(0xFFFFF4E5);
        fg = const Color(0xFFD97706);
      case 'leave':
        bg = const Color(0xFFEEF2FF);
        fg = const Color(0xFF4F46E5);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
