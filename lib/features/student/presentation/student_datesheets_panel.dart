import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/student_api.dart';
import '../models/student_bootstrap.dart';

class StudentDatesheetsPanel extends StatefulWidget {
  const StudentDatesheetsPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentDatesheetsPanel> createState() => _StudentDatesheetsPanelState();
}

class _StudentDatesheetsPanelState extends State<StudentDatesheetsPanel> {
  final _api = StudentApi();
  List<Map<String, dynamic>> _sheets = [];
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
      final sheets = await _api.fetchDatesheets(
        token: widget.token,
        academicYearId: widget.bootstrap.academicYearId,
      );
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
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
        _error = 'Could not load datesheets. Please try again.';
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
        child: _sheets.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No datesheets published yet', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _sheets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final sheet = _sheets[index];
                  final entries = (sheet['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
                        Text(sheet['name'] as String? ?? 'Datesheet', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (entries.isEmpty)
                          const Text('No entries for your class', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
                        else
                          ...entries.map((entry) {
                            final subject = (entry['subject'] as Map?)?['name'] as String? ?? '—';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '$subject · ${entry['startTime']} – ${entry['endTime']}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
