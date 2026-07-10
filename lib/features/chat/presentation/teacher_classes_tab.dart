import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../teacher/models/teacher_bootstrap.dart';

class TeacherClassesTab extends StatelessWidget {
  const TeacherClassesTab({super.key, required this.bootstrap});

  final TeacherBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    final byClass = <String, List<TeacherAssignment>>{};
    for (final assignment in bootstrap.assignments) {
      byClass.putIfAbsent(assignment.groupId, () => []).add(assignment);
    }

    if (byClass.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No class assignments yet', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          bootstrap.academicYearLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${bootstrap.assignmentCount} assignment${bootstrap.assignmentCount == 1 ? '' : 's'}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...byClass.entries.map((entry) {
          final assignments = entry.value;
          final sample = assignments.first;
          final subjects = assignments.map((a) => a.subjectName).toList();
          final isClassTeacher = assignments.any((a) => a.isClassTeacher);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.violet.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.groups_rounded, color: AppColors.violet),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sample.classLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            if (isClassTeacher)
                              const Text('Class teacher', style: TextStyle(color: AppColors.violet, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subjects
                        .map(
                          (name) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
