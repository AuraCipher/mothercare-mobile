import 'package:flutter/material.dart';

import '../../../core/portal/models/results_table.dart';
import '../../../core/storage/dashboard_cache_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_filter_dropdown.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../../portal/widgets/results_marks_list.dart';
import '../data/student_api.dart';
import '../models/student_bootstrap.dart';

class StudentResultsPanel extends StatefulWidget {
  const StudentResultsPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentResultsPanel> createState() => _StudentResultsPanelState();
}

class _StudentResultsPanelState extends State<StudentResultsPanel> {
  final _api = StudentApi();
  final _cache = DashboardCacheStore.instance;
  ResultsTableData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  String _sessionId = 'all';
  String _examTypeId = 'all';
  String _subjectId = 'all';

  String get _cacheKey =>
      'dashboard_student_results_${widget.bootstrap.academicYearId}_$_sessionId$_examTypeId$_subjectId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await runPortalLoad<ResultsTableData>(
      fetch: () => _api.fetchResultsTable(
        token: widget.token,
        academicYearId: widget.bootstrap.academicYearId,
        sessionId: _sessionId == 'all' ? null : _sessionId,
        examTypeId: _examTypeId == 'all' ? null : _examTypeId,
        subjectId: _subjectId == 'all' ? null : _subjectId,
      ),
      readCache: () async {
        final raw = await _cache.readData(_cacheKey);
        return raw == null ? null : ResultsTableData.fromJson(raw);
      },
      saveCache: (data) =>
          _cache.save(key: _cacheKey, category: 'dashboard_student_results', data: data.toJson()),
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

  void _setFilter({String? sessionId, String? examTypeId, String? subjectId}) {
    setState(() {
      if (sessionId != null) {
        _sessionId = sessionId;
        _examTypeId = 'all';
      }
      if (examTypeId != null) _examTypeId = examTypeId;
      if (subjectId != null) _subjectId = subjectId;
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
                  const SizedBox(height: 16),
                  ResultsMarksList(rows: data.rows),
                ],
              ),
            ),
    );
  }
}
