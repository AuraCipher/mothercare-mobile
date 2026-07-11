import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/student_api.dart';
import '../models/student_bootstrap.dart';

class StudentCanteenPanel extends StatefulWidget {
  const StudentCanteenPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentCanteenPanel> createState() => _StudentCanteenPanelState();
}

class _StudentCanteenPanelState extends State<StudentCanteenPanel> {
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
      final data = await _api.fetchCanteen(
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
        _error = 'Could not load canteen account';
        _loading = false;
      });
    }
  }

  String _money(dynamic value) {
    final amount = value is num ? value : 0;
    return NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final sales = (_data?['sales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return PortalPanelScaffold(
      loading: _loading,
      offline: false,
      error: _error,
      onRetry: _load,
      child: RefreshIndicator(
        color: AppColors.violet,
        onRefresh: _load,
        child: _data == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No canteen account linked', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_data?['displayName'] as String? ?? 'Canteen', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('Balance ${_money(_data?['runningBalance'])}', style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Recent purchases', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (sales.isEmpty)
                    const Text('No purchases yet', style: TextStyle(color: AppColors.textMuted, fontSize: 12))
                  else
                    ...sales.map((sale) {
                      final soldAt = DateTime.tryParse(sale['soldAt']?.toString() ?? '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                soldAt != null ? DateFormat('d MMM yyyy').format(soldAt.toLocal()) : '—',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            ),
                            Text(_money(sale['totalAmount']), style: const TextStyle(fontWeight: FontWeight.w600)),
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
