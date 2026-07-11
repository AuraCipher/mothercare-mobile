import '../../../core/api/authenticated_client.dart';
import '../../../core/portal/models/results_table.dart';
import '../models/student_attendance.dart';
import '../models/student_bootstrap.dart';
import '../models/student_fees.dart';

class StudentApi {
  StudentApi({AuthenticatedClient? client}) : _client = client ?? AuthenticatedClient();

  final AuthenticatedClient _client;

  Map<String, String> _scope(String academicYearId) => {'academicYearId': academicYearId};

  Future<StudentBootstrap> fetchBootstrap({required String token}) async {
    final body = await _client.getJson('/student/bootstrap', token: token);
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return StudentBootstrap.fromJson(data);
  }

  Future<StudentFeesData> fetchFees({
    required String token,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/student/fees',
      token: token,
      query: _scope(academicYearId),
    );
    return StudentFeesData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<StudentAttendanceData> fetchAttendance({
    required String token,
    required String academicYearId,
    String? from,
    String? to,
  }) async {
    final query = _scope(academicYearId);
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    final body = await _client.getJson('/student/attendance', token: token, query: query);
    return StudentAttendanceData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<ResultsTableData> fetchResultsTable({
    required String token,
    required String academicYearId,
    String? sessionId,
    String? examTypeId,
    String? subjectId,
  }) async {
    final query = _scope(academicYearId);
    if (sessionId != null && sessionId.isNotEmpty) query['sessionId'] = sessionId;
    if (examTypeId != null && examTypeId.isNotEmpty) query['examTypeId'] = examTypeId;
    if (subjectId != null && subjectId.isNotEmpty) query['subjectId'] = subjectId;
    final body = await _client.getJson('/student/results/table', token: token, query: query);
    return ResultsTableData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<Map<String, dynamic>> fetchProfile({required String token}) async {
    final body = await _client.getJson('/student/profile', token: token);
    return body['data'] as Map<String, dynamic>? ?? {};
  }
}
