class StudentBootstrap {
  const StudentBootstrap({
    required this.academicYearId,
    required this.academicYearLabel,
    required this.branchName,
    required this.userName,
    this.groupLabel,
    this.studentName,
    this.rollNumber,
  });

  final String academicYearId;
  final String academicYearLabel;
  final String branchName;
  final String userName;
  final String? groupLabel;
  final String? studentName;
  final String? rollNumber;

  factory StudentBootstrap.fromJson(Map<String, dynamic> json) {
    final ay = json['academicYear'] as Map<String, dynamic>? ?? {};
    final student = json['student'] as Map<String, dynamic>? ?? {};
    final branch = json['branch'] as Map<String, dynamic>? ?? {};
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return StudentBootstrap(
      academicYearId: ay['id'] as String? ?? '',
      academicYearLabel: ay['label'] as String? ?? '',
      branchName: branch['name'] as String? ?? '',
      userName: user['name'] as String? ?? student['name'] as String? ?? '',
      groupLabel: student['groupLabel'] as String?,
      studentName: student['name'] as String? ?? '',
      rollNumber: student['rollNumber'] as String?,
    );
  }
}
