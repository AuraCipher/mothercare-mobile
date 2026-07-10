class TeacherAssignment {
  const TeacherAssignment({
    required this.id,
    required this.groupId,
    required this.subjectId,
    required this.isClassTeacher,
    required this.groupName,
    this.groupSection,
    required this.subjectName,
  });

  final String id;
  final String groupId;
  final String subjectId;
  final bool isClassTeacher;
  final String groupName;
  final String? groupSection;
  final String subjectName;

  String get classLabel {
    final section = groupSection?.trim();
    if (section != null && section.isNotEmpty) return '$groupName · $section';
    return groupName;
  }

  factory TeacherAssignment.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>? ?? {};
    final subject = json['subject'] as Map<String, dynamic>? ?? {};
    return TeacherAssignment(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? group['id'] as String? ?? '',
      subjectId: json['subjectId'] as String? ?? subject['id'] as String? ?? '',
      isClassTeacher: json['isClassTeacher'] as bool? ?? false,
      groupName: group['name'] as String? ?? '',
      groupSection: group['section'] as String?,
      subjectName: subject['name'] as String? ?? '',
    );
  }
}

class TeacherBootstrap {
  const TeacherBootstrap({
    required this.academicYearId,
    required this.academicYearLabel,
    required this.branchId,
    required this.branchName,
    required this.userName,
    required this.assignments,
    this.isHod = false,
    this.assignmentCount = 0,
    this.portalAccess = 'FULL',
  });

  final String academicYearId;
  final String academicYearLabel;
  final String branchId;
  final String branchName;
  final String userName;
  final List<TeacherAssignment> assignments;
  final bool isHod;
  final int assignmentCount;
  final String portalAccess;

  factory TeacherBootstrap.fromJson(Map<String, dynamic> json) {
    final ay = json['academicYear'] as Map<String, dynamic>? ?? {};
    final branch = json['branch'] as Map<String, dynamic>? ?? {};
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final portal = json['portal'] as Map<String, dynamic>? ?? {};
    final assignmentsRaw = json['assignments'] as List<dynamic>? ?? [];
    return TeacherBootstrap(
      academicYearId: ay['id'] as String? ?? '',
      academicYearLabel: ay['label'] as String? ?? '',
      branchId: branch['id'] as String? ?? '',
      branchName: branch['name'] as String? ?? '',
      userName: user['name'] as String? ?? '',
      assignments: assignmentsRaw
          .map((e) => TeacherAssignment.fromJson(e as Map<String, dynamic>))
          .toList(),
      isHod: portal['isHod'] as bool? ?? false,
      assignmentCount: portal['assignmentCount'] as int? ?? assignmentsRaw.length,
      portalAccess: portal['portalAccess'] as String? ?? 'FULL',
    );
  }

  Map<String, dynamic> toJson() => {
        'academicYear': {'id': academicYearId, 'label': academicYearLabel},
        'branch': {'id': branchId, 'name': branchName},
        'user': {'name': userName},
        'portal': {
          'isHod': isHod,
          'assignmentCount': assignmentCount,
          'portalAccess': portalAccess,
        },
        'assignments': assignments
            .map(
              (a) => {
                'id': a.id,
                'groupId': a.groupId,
                'subjectId': a.subjectId,
                'isClassTeacher': a.isClassTeacher,
                'group': {'id': a.groupId, 'name': a.groupName, 'section': a.groupSection},
                'subject': {'id': a.subjectId, 'name': a.subjectName},
              },
            )
            .toList(),
      };
}
