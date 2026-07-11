import 'package:flutter/material.dart';

import '../../../core/portal/models/results_table.dart';
import '../../../core/storage/dashboard_cache_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_filter_dropdown.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../../portal/widgets/results_marks_list.dart';
import '../data/teacher_api.dart';
import '../models/teacher_bootstrap.dart';

class TeacherResultsPanel extends StatefulWidget {
  const TeacherResultsPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherResultsPanel> createState() => _TeacherResultsPanelState();
}

class _TeacherResultsPanelState extends State<TeacherResultsPanel> {
  final _api = TeacherApi();
  final _cache = DashboardCacheStore.instance;
  ResultsTableData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  String _sessionId = 'all';
  String _examTypeId = 'all';
  String _subjectId = 'all';
  String _studentId = 'all';

  String get _cacheKey =>
      'dashboard_teacher_results_${widget.bootstrap.academicYearId}_${_sessionId}_${_examTypeId}_${_subjectId}_$_studentId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await runPortalLoad<ResultsTableData>(
      fetch: () => _api.fetchResultsTable(
        token: widget.token,
        bootstrap: widget.bootstrap,
        sessionId: _sessionId == 'all' ? null : _sessionId,
        examTypeId: _examTypeId == 'all' ? null : _examTypeId,
        subjectId: _subjectId == 'all' ? null : _subjectId,
        studentId: _studentId == 'all' ? null : _studentId,
      ),
      readCache: () async {
        final raw = await _cache.readData(_cacheKey);
        return raw == null ? null : ResultsTableData.fromJson(raw);
      },
      saveCache: (data) =>
          _cache.save(key: _cacheKey, category: 'dashboard_teacher_results', data: data.toJson()),
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

  void _setFilter({String? sessionId, String? examTypeId, String? subjectId, String? studentId}) {
    setState(() {
      if (sessionId != null) {
        _sessionId = sessionId;
        _examTypeId = 'all';
      }
      if (examTypeId != null) _examTypeId = examTypeId;
      if (subjectId != null) _subjectId = subjectId;
      if (studentId != null) _studentId = studentId;
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final filters = data?.filters ?? const ResultsFiltersMeta();
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
                    label: 'Session',
                    value: _sessionId,
                    options: filters.sessions.map((e) => PortalFilterOption(id: e.id, label: e.name)).toList(),
                    onChanged: (v) => _setFilter(sessionId: v),
                  ),
                  const SizedBox(height: 10),
                  PortalFilterDropdown(
                    label: 'Exam type',
                    value: _examTypeId,
                    options: filters.examTypes.map((e) => PortalFilterOption(id: e.id, label: e.name)).toList(),
                    onChanged: (v) => _setFilter(examTypeId: v),
                  ),
                  const SizedBox(height: 10),
                  PortalFilterDropdown(
                    label: 'Subject',
                    value: _subjectId,
                    options: filters.subjects.map((e) => PortalFilterOption(id: e.id, label: e.name)).toList(),
                    onChanged: (v) => _setFilter(subjectId: v),
                  ),
                  const SizedBox(height: 10),
                  PortalFilterDropdown(
                    label: 'Student',
                    value: _studentId,
                    options: filters.students
                        .map(
                          (e) => PortalFilterOption(
                            id: e.id,
                            label: e.rollNumber != null ? '${e.name} (Roll ${e.rollNumber})' : e.name,
                          ),
                        )
                        .toList(),
                    onChanged: (v) => _setFilter(studentId: v),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Read-only results — marks entry stays on the web portal.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  ResultsMarksList(rows: data.rows, showStudent: true, showGroup: true),
                ],
              ),
            ),
    );
  }
}
