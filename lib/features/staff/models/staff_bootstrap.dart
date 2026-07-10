class StaffBootstrap {
  const StaffBootstrap({
    required this.academicYearId,
    required this.academicYearLabel,
    required this.branchId,
    required this.branchName,
    required this.userName,
    required this.role,
  });

  final String academicYearId;
  final String academicYearLabel;
  final String branchId;
  final String branchName;
  final String userName;
  final String role;

  String get roleLabel {
    switch (role) {
      case 'branch_admin':
        return 'Principal';
      case 'sub_admin':
        return 'Sub Admin';
      case 'management':
        return 'Management';
      default:
        return role;
    }
  }

  Map<String, dynamic> toJson() => {
        'academicYearId': academicYearId,
        'academicYearLabel': academicYearLabel,
        'branchId': branchId,
        'branchName': branchName,
        'userName': userName,
        'role': role,
      };

  factory StaffBootstrap.fromJson(Map<String, dynamic> json) {
    return StaffBootstrap(
      academicYearId: json['academicYearId'] as String? ?? '',
      academicYearLabel: json['academicYearLabel'] as String? ?? '',
      branchId: json['branchId'] as String? ?? '',
      branchName: json['branchName'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }
}
