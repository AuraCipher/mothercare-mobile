import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/dashboard_cache_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_filter_dropdown.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/teacher_api.dart';
import '../models/teacher_attendance.dart';
import '../models/teacher_bootstrap.dart';

class TeacherAttendancePanel extends StatefulWidget {
  const TeacherAttendancePanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherAttendancePanel> createState() => _TeacherAttendancePanelState();
}

class _TeacherAttendancePanelState extends State<TeacherAttendancePanel> {
  final _api = TeacherApi();
  final _cache = DashboardCacheStore.instance;
  TeacherAttendanceData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  late String _groupId;
  late DateTime _date;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_date);

  String get _cacheKey => 'dashboard_teacher_attendance_${_groupId}_$_dateKey';

  List<PortalFilterOption> get _classOptions {
    final seen = <String>{};
    final options = <PortalFilterOption>[];
    for (final assignment in widget.bootstrap.assignments) {
      if (seen.add(assignment.groupId)) {
        options.add(PortalFilterOption(id: assignment.groupId, label: assignment.classLabel));
      }
    }
    return options;
  }

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _groupId = _classOptions.isNotEmpty ? _classOptions.first.id : '';
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _data = null;
    });
    _load();
  }

  Future<void> _load() async {
    if (_groupId.isEmpty) {
      setState(() {
        _loading = false;
        _data = TeacherAttendanceData(date: _dateKey, groupId: _groupId);
      });
      return;
    }

    await runPortalLoad<TeacherAttendanceData>(
      fetch: () => _api.fetchAttendance(
        token: widget.token,
        bootstrap: widget.bootstrap,
        groupId: _groupId,
        date: _dateKey,
      ),
      readCache: () async {
        final raw = await _cache.readData(_cacheKey);
        return raw == null ? null : TeacherAttendanceData.fromJson(raw);
      },
      saveCache: (data) =>
          _cache.save(key: _cacheKey, category: 'dashboard_teacher_attendance', data: data.toJson()),
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

  Color _statusColor(String? status) {
    switch (status) {
      case 'present':
        return const Color(0xFF059669);
      case 'late':
        return const Color(0xFFD97706);
      case 'leave':
      case 'function':
        return const Color(0xFF0284C7);
      case null:
      case '':
        return AppColors.textMuted;
      default:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final classOptions = _classOptions;

    return PortalPanelScaffold(
      loading: _loading,
      offline: _offline,
      error: _error,
      onRetry: _load,
      child: classOptions.isEmpty
          ? const Center(child: Text('No class assignments yet', style: TextStyle(color: AppColors.textMuted)))
          : RefreshIndicator(
              color: AppColors.violet,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  PortalFilterDropdown(
                    label: 'Class',
                    value: _groupId,
                    includeAll: false,
                    options: classOptions,
                    onChanged: (value) {
                      setState(() {
                        _groupId = value;
                        _data = null;
                      });
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                      ),
                      child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Read-only view — attendance marking stays on the web portal.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  if (data != null && data.records.isEmpty)
                    const Text('No attendance records for this class and date.', style: TextStyle(color: AppColors.textMuted))
                  else if (data != null)
                    ...data.records.map((row) {
                      final status = row.status ?? 'unmarked';
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
                                  Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (row.rollNumber != null)
                                    Text('Roll ${row.rollNumber}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                                status,
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
