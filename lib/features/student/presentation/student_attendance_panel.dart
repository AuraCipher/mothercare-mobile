import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/dashboard_cache_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_filter_dropdown.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../../portal/widgets/portal_stat_card.dart';
import '../data/student_api.dart';
import '../models/student_attendance.dart';
import '../models/student_bootstrap.dart';

enum _AttendanceRange { all, thisMonth, last30 }

class StudentAttendancePanel extends StatefulWidget {
  const StudentAttendancePanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentAttendancePanel> createState() => _StudentAttendancePanelState();
}

class _StudentAttendancePanelState extends State<StudentAttendancePanel> {
  final _api = StudentApi();
  final _cache = DashboardCacheStore.instance;
  StudentAttendanceData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;
  _AttendanceRange _range = _AttendanceRange.all;

  String get _rangeKey => _range.name;

  String get _cacheKey =>
      'dashboard_student_attendance_${widget.bootstrap.academicYearId}_$_rangeKey';

  (String?, String?) _rangeDates() {
    final now = DateTime.now();
    switch (_range) {
      case _AttendanceRange.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        return (_iso(start), _iso(now));
      case _AttendanceRange.last30:
        return (_iso(now.subtract(const Duration(days: 30))), _iso(now));
      case _AttendanceRange.all:
        return (null, null);
    }
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (from, to) = _rangeDates();
    await runPortalLoad<StudentAttendanceData>(
      fetch: () => _api.fetchAttendance(
        token: widget.token,
        academicYearId: widget.bootstrap.academicYearId,
        from: from,
        to: to,
      ),
      readCache: () async {
        final raw = await _cache.readData(_cacheKey);
        return raw == null ? null : StudentAttendanceData.fromJson(raw);
      },
      saveCache: (data) =>
          _cache.save(key: _cacheKey, category: 'dashboard_student_attendance', data: data.toJson()),
      onLoading: ({required loading}) {
        if (!mounted) return;
        setState(() => _loading = loading && _data == null);
      },
      onData: (data, {required offline}) {
        if (!mounted) return;
        setState(() {
          _data = data;
          _offline = offline;
          _error = null;
        });
      },
      onError: (message, {required offline}) {
        if (!mounted) return;
        setState(() {
          _offline = offline;
          _error = message.isEmpty ? null : message;
        });
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return const Color(0xFF059669);
      case 'late':
        return const Color(0xFFD97706);
      case 'leave':
      case 'function':
        return const Color(0xFF0284C7);
      default:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return PortalPanelScaffold(
      loading: _loading,
      offline: _offline,
      error: _error,
      onRetry: _load,
      child: data == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              color: AppColors.violet,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  PortalFilterDropdown(
                    label: 'Period',
                    value: _range.name,
                    includeAll: false,
                    options: const [
                      PortalFilterOption(id: 'all', label: 'Full academic year'),
                      PortalFilterOption(id: 'thisMonth', label: 'This month'),
                      PortalFilterOption(id: 'last30', label: 'Last 30 days'),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _range = _AttendanceRange.values.firstWhere((e) => e.name == value);
                        _data = null;
                      });
                      _load();
                    },
                  ),
                  const SizedBox(height: 14),
                  PortalStatRow(
                    children: [
                      PortalStatCard(label: 'Attendance rate', value: '${data.summary.percentage}%'),
                      PortalStatCard(
                        label: 'Present',
                        value: '${data.summary.present}',
                        valueColor: const Color(0xFF059669),
                      ),
                      PortalStatCard(
                        label: 'Absent / Late',
                        value: '${data.summary.absent} / ${data.summary.late}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data.records.isEmpty)
                    const Text('No attendance records for this period.', style: TextStyle(color: AppColors.textMuted))
                  else
                    ...data.records.map((row) {
                      final label = DateFormat('EEE, d MMM').format(row.date);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (row.note != null && row.note!.isNotEmpty)
                                    Text(row.note!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(row.status).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                row.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(row.status),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
