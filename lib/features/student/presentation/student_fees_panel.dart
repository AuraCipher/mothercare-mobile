import 'package:flutter/material.dart';

import '../../../core/portal/money_format.dart';
import '../../../core/storage/dashboard_cache_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../portal/widgets/portal_panel_scaffold.dart';
import '../../portal/widgets/portal_stat_card.dart';
import '../data/student_api.dart';
import '../models/student_bootstrap.dart';
import '../models/student_fees.dart';

class StudentFeesPanel extends StatefulWidget {
  const StudentFeesPanel({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  State<StudentFeesPanel> createState() => _StudentFeesPanelState();
}

class _StudentFeesPanelState extends State<StudentFeesPanel> {
  final _api = StudentApi();
  final _cache = DashboardCacheStore.instance;
  StudentFeesData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  String get _cacheKey => 'dashboard_student_fees_${widget.bootstrap.academicYearId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await runPortalLoad<StudentFeesData>(
      fetch: () => _api.fetchFees(token: widget.token, academicYearId: widget.bootstrap.academicYearId),
      readCache: () async {
        final raw = await _cache.readData(_cacheKey);
        return raw == null ? null : StudentFeesData.fromJson(raw);
      },
      saveCache: (data) => _cache.save(key: _cacheKey, category: 'dashboard_student_fees', data: data.toJson()),
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
      case 'PAID':
        return const Color(0xFF059669);
      case 'PARTIAL':
        return const Color(0xFFD97706);
      case 'OVERPAID':
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
                  PortalStatRow(
                    children: [
                      PortalStatCard(label: 'Balance due', value: formatMoneyPaise(data.summary.balanceDuePaise)),
                      PortalStatCard(label: 'Total paid', value: formatMoneyPaise(data.summary.totalPaidPaise)),
                      PortalStatCard(label: 'Unpaid months', value: '${data.summary.unpaidCount}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data.months.isEmpty)
                    const Text('No fee records for this academic year.', style: TextStyle(color: AppColors.textMuted))
                  else
                    ...data.months.map((month) {
                      final monthLabel = month.month >= 1 && month.month <= 12
                          ? '${studentFeeMonthNames[month.month]} ${month.year}'
                          : '${month.year}';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(monthLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text(
                                        month.status,
                                        style: TextStyle(color: _statusColor(month.status), fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Paid: ${formatMoneyPaise(month.paidAmount)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                    if (month.dueAmount > 0)
                                      Text(
                                        'Due: ${formatMoneyPaise(month.dueAmount)}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (month.extraItems.isNotEmpty) ...[
                              const Divider(height: 20),
                              ...month.extraItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(item.name, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                                      Text(formatMoneyPaise(item.amount), style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (month.payments.isNotEmpty) ...[
                              const Divider(height: 20),
                              ...month.payments.map(
                                (payment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          payment.receiptNumber ?? 'Receipt',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text(formatMoneyPaise(payment.amount), style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
