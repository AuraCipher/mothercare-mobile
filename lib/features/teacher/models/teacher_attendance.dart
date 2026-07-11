class TeacherAttendanceRecord {
  const TeacherAttendanceRecord({
    required this.studentId,
    required this.name,
    this.rollNumber,
    this.admissionNumber,
    this.status,
    this.note,
  });

  final String studentId;
  final String name;
  final String? rollNumber;
  final String? admissionNumber;
  final String? status;
  final String? note;

  factory TeacherAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return TeacherAttendanceRecord(
      studentId: json['studentId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      rollNumber: json['rollNumber'] as String?,
      admissionNumber: json['admissionNumber'] as String?,
      status: json['status'] as String?,
      note: json['note'] as String?,
    );
  }
}

class TeacherAttendanceData {
  const TeacherAttendanceData({
    required this.date,
    required this.groupId,
    this.records = const [],
    this.total = 0,
  });

  final String date;
  final String groupId;
  final List<TeacherAttendanceRecord> records;
  final int total;

  factory TeacherAttendanceData.fromJson(Map<String, dynamic> json) {
    final recordsRaw = json['records'] as List<dynamic>? ?? [];
    return TeacherAttendanceData(
      date: json['date'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      records: recordsRaw.map((e) => TeacherAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] is int ? json['total'] as int : int.tryParse('${json['total']}') ?? recordsRaw.length,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'groupId': groupId,
        'total': total,
        'records': records
            .map(
              (r) => {
                'studentId': r.studentId,
                'name': r.name,
                'rollNumber': r.rollNumber,
                'admissionNumber': r.admissionNumber,
                'status': r.status,
                'note': r.note,
              },
            )
            .toList(),
      };
}
