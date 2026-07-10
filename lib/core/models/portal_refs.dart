class AcademicYearRef {
  const AcademicYearRef({
    required this.id,
    required this.label,
    this.branchId,
  });

  final String id;
  final String label;
  final String? branchId;

  factory AcademicYearRef.fromJson(Map<String, dynamic> json) {
    final calendar = json['calendar'] as Map<String, dynamic>? ?? {};
    final branch = json['branch'] as Map<String, dynamic>? ?? {};
    return AcademicYearRef(
      id: json['id'] as String? ?? '',
      label: calendar['label'] as String? ?? json['label'] as String? ?? '',
      branchId: json['branchId'] as String? ?? branch['id'] as String?,
    );
  }
}

class BranchRef {
  const BranchRef({required this.id, required this.name, required this.code, this.role});

  final String id;
  final String name;
  final String code;
  final String? role;

  factory BranchRef.fromJson(Map<String, dynamic> json) {
    final branch = json['branch'] as Map<String, dynamic>? ?? json;
    return BranchRef(
      id: branch['id'] as String? ?? '',
      name: branch['name'] as String? ?? '',
      code: branch['code'] as String? ?? '',
      role: json['role'] as String?,
    );
  }
}
