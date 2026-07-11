import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/teacher_classes_tab.dart';
import '../models/teacher_bootstrap.dart';
import 'teacher_attendance_panel.dart';
import 'teacher_results_panel.dart';
import 'teacher_timetable_panel.dart';
import 'teacher_hod_panel.dart';

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
    final tabs = <Widget>[
      const Tab(text: 'Classes'),
      const Tab(text: "Today's Attendance"),
      const Tab(text: 'Results'),
      const Tab(text: 'Timetable'),
      if (bootstrap.isHod) const Tab(text: 'HOD'),
    ];
    final views = <Widget>[
      TeacherClassesTab(bootstrap: bootstrap),
      TeacherAttendancePanel(token: token, bootstrap: bootstrap),
      TeacherResultsPanel(token: token, bootstrap: bootstrap),
      TeacherTimetablePanel(token: token, bootstrap: bootstrap),
      if (bootstrap.isHod) TeacherHodPanel(token: token, bootstrap: bootstrap),
    ];

    return DefaultTabController(
      length: tabs.length,
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
              tabs: tabs,
            ),
          ),
          Expanded(
            child: TabBarView(children: views),
          ),
        ],
      ),
    );
  }
}
