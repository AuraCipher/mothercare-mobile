import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../data/teacher_api.dart';
import '../models/teacher_bootstrap.dart';

class TeacherMyPayrollPanel extends StatefulWidget {
  const TeacherMyPayrollPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

  @override
  State<TeacherMyPayrollPanel> createState() => _TeacherMyPayrollPanelState();
}

class _TeacherMyPayrollPanelState extends State<TeacherMyPayrollPanel> {
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
      final rows = await _api.fetchMyPayroll(token: widget.token, bootstrap: widget.bootstrap);
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
        _error = 'Could not load payroll history. Please try again.';
        _loading = false;
      });
    }
  }

  String _formatAmount(dynamic paise) {
    final value = (paise is num) ? paise / 100 : 0;
    return NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0).format(value);
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
                  Center(child: Text('No payroll records yet', style: TextStyle(color: AppColors.textMuted))),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final outgoing = row['outgoingPayment'] as Map<String, dynamic>? ?? {};
                  final paidAt = DateTime.tryParse(outgoing['paidAt']?.toString() ?? '');
                  final amount = outgoing['amount'];
                  final method = outgoing['paymentMethod'] as String? ?? '';
                  final voucher = outgoing['voucherNumber'] as String? ?? '—';
                  final salaryMonth = row['salaryMonth'] as String? ?? '';
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                salaryMonth,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(_formatAmount(amount), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.violet)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (paidAt != null) DateFormat('d MMM yyyy').format(paidAt.toLocal()),
                            if (method.isNotEmpty) method.replaceAll('_', ' '),
                            'Voucher $voucher',
                          ].where((s) => s.isNotEmpty).join(' · '),
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
