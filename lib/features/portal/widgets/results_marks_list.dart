import 'package:flutter/material.dart';

import '../../../core/portal/models/results_table.dart';
import '../../../core/theme/app_theme.dart';

class ResultsMarksList extends StatelessWidget {
  const ResultsMarksList({
    super.key,
    required this.rows,
    this.showStudent = false,
    this.showGroup = false,
    this.emptyMessage = 'No results match your filters.',
  });

  final List<ResultsTableRow> rows;
  final bool showStudent;
  final bool showGroup;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(emptyMessage, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      );
    }

    return Column(
      children: rows.map((row) => _ResultCard(row: row, showStudent: showStudent, showGroup: showGroup)).toList(),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.row, required this.showStudent, required this.showGroup});

  final ResultsTableRow row;
  final bool showStudent;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showStudent && row.studentName != null)
            Text(row.studentName!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (showStudent && row.rollNumber != null)
            Text('Roll ${row.rollNumber}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(row.subjectName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '${row.sessionName} · ${row.examTypeName} · ${row.examName}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (showGroup && row.groupLabel != null) ...[
            const SizedBox(height: 2),
            Text(row.groupLabel!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _marksLabel(row)),
              if (row.hasMarks && row.percentage != null)
                Text('${row.percentage!.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _passChip(row),
            ],
          ),
        ],
      ),
    );
  }

  Widget _marksLabel(ResultsTableRow row) {
    if (!row.hasMarks) return const Text('—', style: TextStyle(color: AppColors.textMuted));
    if (row.isAbsent) return const Text('Absent', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w600));
    if (row.marksObtained == null) return const Text('—', style: TextStyle(color: AppColors.textMuted));
    final total = row.totalMarks ?? 100;
    return Text(
      '${row.marksObtained} / $total',
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    );
  }

  Widget _passChip(ResultsTableRow row) {
    if (!row.hasMarks || row.isAbsent) return const SizedBox.shrink();
    final passed = row.passed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (passed ? const Color(0xFF059669) : AppColors.error).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        passed ? 'Pass' : 'Fail',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: passed ? const Color(0xFF059669) : AppColors.error,
        ),
      ),
    );
  }
}
