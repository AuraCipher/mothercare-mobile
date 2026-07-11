import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/teacher_classes_tab.dart';
import '../models/teacher_bootstrap.dart';
import 'teacher_attendance_panel.dart';
import 'teacher_results_panel.dart';

class TeacherWorkspaceTab extends StatelessWidget {
  const TeacherWorkspaceTab({
    super.key,
    required this.token,
    required this.bootstrap,
  });

  final String token;
  final TeacherBootstrap bootstrap;

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
              isScrollable: true,
              tabs: const [
                Tab(text: 'Classes'),
                Tab(text: "Today's Attendance"),
                Tab(text: 'Results'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                TeacherClassesTab(bootstrap: bootstrap),
                TeacherAttendancePanel(token: token, bootstrap: bootstrap),
                TeacherResultsPanel(token: token, bootstrap: bootstrap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
