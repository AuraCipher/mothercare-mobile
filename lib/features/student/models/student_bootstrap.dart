class StudentBootstrap {
  const StudentBootstrap({
    required this.academicYearId,
    required this.academicYearLabel,
    required this.groupLabel,
    required this.studentName,
  });

  final String academicYearId;
  final String academicYearLabel;
  final String? groupLabel;
  final String studentName;

  factory StudentBootstrap.fromJson(Map<String, dynamic> json) {
    final ay = json['academicYear'] as Map<String, dynamic>? ?? {};
    final student = json['student'] as Map<String, dynamic>? ?? {};
    return StudentBootstrap(
      academicYearId: ay['id'] as String? ?? '',
      academicYearLabel: ay['label'] as String? ?? '',
      groupLabel: student['groupLabel'] as String?,
      studentName: student['name'] as String? ?? '',
    );
  }
}
