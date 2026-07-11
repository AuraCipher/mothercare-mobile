import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/staff_api.dart';
import '../models/staff_bootstrap.dart';

class StaffCampusTab extends StatefulWidget {
  const StaffCampusTab({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StaffBootstrap bootstrap;

  @override
  State<StaffCampusTab> createState() => _StaffCampusTabState();
}

class _StaffCampusTabState extends State<StaffCampusTab> with SingleTickerProviderStateMixin {
  final _api = StaffApi();
  late final TabController _tabController;

  Map<String, dynamic>? _overview;
  Map<String, dynamic>? _fees;
  Map<String, dynamic>? _attendance;
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _results = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchCampusOverview(token: widget.token, bootstrap: widget.bootstrap),
        _api.fetchCampusFees(token: widget.token, bootstrap: widget.bootstrap),
        _api.fetchCampusAttendance(token: widget.token, bootstrap: widget.bootstrap),
        _api.fetchCampusStaff(token: widget.token, bootstrap: widget.bootstrap),
        _api.fetchCampusResults(token: widget.token, bootstrap: widget.bootstrap),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as Map<String, dynamic>;
        _fees = results[1] as Map<String, dynamic>;
        _attendance = results[2] as Map<String, dynamic>;
        _staff = results[3] as List<Map<String, dynamic>>;
        _results = results[4] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load campus data';
        _loading = false;
      });
    }
  }

  String _money(dynamic value) {
    final amount = value is num ? value : 0;
    return NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0).format(amount);
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.violet,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.violet,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Attendance'),
              Tab(text: 'Fees'),
              Tab(text: 'Staff'),
              Tab(text: 'Results'),
            ],
          ),
        ),
        Expanded(
          child: PortalPanelScaffold(
            loading: _loading,
            offline: false,
            error: _error,
            onRetry: _load,
            child: TabBarView(
              controller: _tabController,
              children: [
                _overviewTab(),
                _attendanceTab(),
                _feesTab(),
                _staffTab(),
                _resultsTab(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _overviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _statCard('Students', '${_overview?['studentCount'] ?? 0}'),
            const SizedBox(width: 8),
            _statCard('Classes', '${_overview?['classCount'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _statCard('Teachers', '${_overview?['teacherCount'] ?? 0}'),
            const SizedBox(width: 8),
            _statCard('Staff', '${_overview?['staffCount'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Read-only campus snapshot', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _attendanceTab() {
    final summary = _attendance?['summary'] as Map<String, dynamic>? ?? {};
    final classes = (_attendance?['classes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Today · ${_attendance?['date'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          'Present ${summary['present'] ?? 0} · Absent ${summary['absent'] ?? 0} · Late ${summary['late'] ?? 0}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        ...classes.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(row['groupName'] as String? ?? 'Class')),
                    Text('${row['present'] ?? 0}/${row['total'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _feesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Fees · ${_fees?['month']}/${_fees?['year']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _statCard('Collected', _money(_fees?['totalCollected'])),
        const SizedBox(height: 8),
        _statCard('Due', _money(_fees?['totalDue'])),
        const SizedBox(height: 8),
        Text(
          '${_fees?['pendingCount'] ?? 0} pending · ${_fees?['collectionRate'] ?? 0}% collected',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _staffTab() {
    if (_staff.isEmpty) {
      return const Center(child: Text('No staff records', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final member = _staff[index];
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
              Text(member['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${member['branchRole'] ?? member['userRole'] ?? ''} · ${member['status'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resultsTab() {
    if (_results.isEmpty) {
      return const Center(child: Text('No exam sessions', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = _results[index];
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
              Text(session['name'] as String? ?? 'Exam', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${session['examCount'] ?? 0} exams · ${session['startDate'] != null ? String(session['startDate']).slice(0, 10) : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}
