class StudentAttendanceRecord {
  const StudentAttendanceRecord({
    required this.date,
    required this.status,
    this.note,
  });

  final DateTime date;
  final String status;
  final String? note;

  factory StudentAttendanceRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['date'] as String?;
    return StudentAttendanceRecord(
      date: raw != null ? DateTime.tryParse(raw) ?? DateTime.now() : DateTime.now(),
      status: json['status'] as String? ?? 'absent',
      note: json['note'] as String?,
    );
  }
}

class StudentAttendanceSummary {
  const StudentAttendanceSummary({
    required this.present,
    required this.absent,
    required this.late,
    required this.total,
    required this.percentage,
  });

  final int present;
  final int absent;
  final int late;
  final int total;
  final num percentage;

  factory StudentAttendanceSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return StudentAttendanceSummary(
      present: parseInt(json['present']),
      absent: parseInt(json['absent']),
      late: parseInt(json['late']),
      total: parseInt(json['total']),
      percentage: json['percentage'] is num ? json['percentage'] as num : num.tryParse('${json['percentage']}') ?? 0,
    );
  }
}

class StudentAttendanceData {
  const StudentAttendanceData({
    this.records = const [],
    required this.summary,
  });

  final List<StudentAttendanceRecord> records;
  final StudentAttendanceSummary summary;

  factory StudentAttendanceData.fromJson(Map<String, dynamic> json) {
    final recordsRaw = json['records'] as List<dynamic>? ?? [];
    return StudentAttendanceData(
      records: recordsRaw.map((e) => StudentAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList(),
      summary: StudentAttendanceSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'records': records
            .map(
              (r) => {
                'date': r.date.toUtc().toIso8601String(),
                'status': r.status,
                'note': r.note,
              },
            )
            .toList(),
        'summary': {
          'present': summary.present,
          'absent': summary.absent,
          'late': summary.late,
          'total': summary.total,
          'percentage': summary.percentage,
        },
      };
}
