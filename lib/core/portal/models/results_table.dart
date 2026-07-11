class ResultsFilterOption {
  const ResultsFilterOption({required this.id, required this.name, this.rollNumber});

  final String id;
  final String name;
  final String? rollNumber;

  factory ResultsFilterOption.fromJson(Map<String, dynamic> json) {
    return ResultsFilterOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      rollNumber: json['rollNumber'] as String?,
    );
  }
}

class ResultsFiltersMeta {
  const ResultsFiltersMeta({
    this.sessions = const [],
    this.examTypes = const [],
    this.subjects = const [],
    this.students = const [],
  });

  final List<ResultsFilterOption> sessions;
  final List<ResultsFilterOption> examTypes;
  final List<ResultsFilterOption> subjects;
  final List<ResultsFilterOption> students;

  factory ResultsFiltersMeta.fromJson(Map<String, dynamic> json) {
    List<ResultsFilterOption> parseList(String key) {
      final raw = json[key] as List<dynamic>? ?? [];
      return raw.map((e) => ResultsFilterOption.fromJson(e as Map<String, dynamic>)).toList();
    }

    return ResultsFiltersMeta(
      sessions: parseList('sessions'),
      examTypes: parseList('examTypes'),
      subjects: parseList('subjects'),
      students: parseList('students'),
    );
  }
}

class ResultsTableRow {
  const ResultsTableRow({
    required this.marksEntryId,
    this.studentId,
    this.studentName,
    this.rollNumber,
    required this.sessionId,
    required this.sessionName,
    required this.examTypeId,
    required this.examTypeName,
    required this.examId,
    required this.examName,
    required this.subjectId,
    required this.subjectName,
    this.groupLabel,
    this.marksObtained,
    this.totalMarks,
    this.passingMarks,
    this.isAbsent = false,
    this.percentage,
    this.passed = false,
    this.hasMarks = false,
  });

  final String marksEntryId;
  final String? studentId;
  final String? studentName;
  final String? rollNumber;
  final String sessionId;
  final String sessionName;
  final String examTypeId;
  final String examTypeName;
  final String examId;
  final String examName;
  final String subjectId;
  final String subjectName;
  final String? groupLabel;
  final num? marksObtained;
  final num? totalMarks;
  final num? passingMarks;
  final bool isAbsent;
  final num? percentage;
  final bool passed;
  final bool hasMarks;

  factory ResultsTableRow.fromJson(Map<String, dynamic> json) {
    return ResultsTableRow(
      marksEntryId: json['marksEntryId'] as String? ?? '',
      studentId: json['studentId'] as String?,
      studentName: json['studentName'] as String?,
      rollNumber: json['rollNumber'] as String?,
      sessionId: json['sessionId'] as String? ?? '',
      sessionName: json['sessionName'] as String? ?? '',
      examTypeId: json['examTypeId'] as String? ?? '',
      examTypeName: json['examTypeName'] as String? ?? '',
      examId: json['examId'] as String? ?? '',
      examName: json['examName'] as String? ?? '',
      subjectId: json['subjectId'] as String? ?? '',
      subjectName: json['subjectName'] as String? ?? '',
      groupLabel: json['groupLabel'] as String?,
      marksObtained: json['marksObtained'] as num?,
      totalMarks: json['totalMarks'] as num?,
      passingMarks: json['passingMarks'] as num?,
      isAbsent: json['isAbsent'] as bool? ?? false,
      percentage: json['percentage'] as num?,
      passed: json['passed'] as bool? ?? false,
      hasMarks: json['hasMarks'] as bool? ?? false,
    );
  }
}

class ResultsTableData {
  const ResultsTableData({
    required this.filters,
    required this.rows,
    this.total = 0,
  });

  final ResultsFiltersMeta filters;
  final List<ResultsTableRow> rows;
  final int total;

  factory ResultsTableData.fromJson(Map<String, dynamic> json) {
    final rowsRaw = json['rows'] as List<dynamic>? ?? [];
    return ResultsTableData(
      filters: ResultsFiltersMeta.fromJson(json['filters'] as Map<String, dynamic>? ?? {}),
      rows: rowsRaw.map((e) => ResultsTableRow.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] is int ? json['total'] as int : int.tryParse('${json['total']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'filters': {
          'sessions': filters.sessions.map((e) => {'id': e.id, 'name': e.name}).toList(),
          'examTypes': filters.examTypes.map((e) => {'id': e.id, 'name': e.name}).toList(),
          'subjects': filters.subjects.map((e) => {'id': e.id, 'name': e.name}).toList(),
          'students': filters.students
              .map((e) => {'id': e.id, 'name': e.name, 'rollNumber': e.rollNumber})
              .toList(),
        },
        'rows': rows
            .map(
              (r) => {
                'marksEntryId': r.marksEntryId,
                'studentId': r.studentId,
                'studentName': r.studentName,
                'rollNumber': r.rollNumber,
                'sessionId': r.sessionId,
                'sessionName': r.sessionName,
                'examTypeId': r.examTypeId,
                'examTypeName': r.examTypeName,
                'examId': r.examId,
                'examName': r.examName,
                'subjectId': r.subjectId,
                'subjectName': r.subjectName,
                'groupLabel': r.groupLabel,
                'marksObtained': r.marksObtained,
                'totalMarks': r.totalMarks,
                'passingMarks': r.passingMarks,
                'isAbsent': r.isAbsent,
                'percentage': r.percentage,
                'passed': r.passed,
                'hasMarks': r.hasMarks,
              },
            )
            .toList(),
        'total': total,
      };
}
