import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/student_bootstrap.dart';
import 'student_attendance_panel.dart';
import 'student_fees_panel.dart';
import 'student_results_panel.dart';

class StudentAcademicsTab extends StatelessWidget {
  const StudentAcademicsTab({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final StudentBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surface,
            child: TabBar(
              labelColor: AppColors.violet,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.violet,
              tabs: const [
                Tab(text: 'Fees'),
                Tab(text: 'Attendance'),
                Tab(text: 'Results'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                StudentFeesPanel(token: token, bootstrap: bootstrap),
                StudentAttendancePanel(token: token, bootstrap: bootstrap),
                StudentResultsPanel(token: token, bootstrap: bootstrap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
