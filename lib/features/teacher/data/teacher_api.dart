import '../../../core/api/authenticated_client.dart';
import '../../../core/api/portal_api.dart';
import '../../../core/portal/models/results_table.dart';
import '../models/teacher_attendance.dart';
import '../models/teacher_bootstrap.dart';

class TeacherApi {
  TeacherApi({AuthenticatedClient? client, PortalApi? portal})
      : _client = client ?? AuthenticatedClient(),
        _portal = portal ?? PortalApi();

  final AuthenticatedClient _client;
  final PortalApi _portal;

  Future<TeacherBootstrap> fetchBootstrap({required String token}) async {
    final branch = await _portal.fetchPrimaryBranch(token: token);
    final academicYearId = await _portal.resolveAcademicYearId(
      token: token,
      branchId: branch.id,
    );
    final body = await _client.getJson(
      '/teacher/bootstrap',
      token: token,
      query: {
        'academicYearId': academicYearId,
        'branchId': branch.id,
      },
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return TeacherBootstrap.fromJson(data);
  }

  Map<String, String> _scope(TeacherBootstrap bootstrap) => {
        'academicYearId': bootstrap.academicYearId,
        'branchId': bootstrap.branchId,
      };

  Future<TeacherAttendanceData> fetchAttendance({
    required String token,
    required TeacherBootstrap bootstrap,
    required String groupId,
    required String date,
  }) async {
    final query = {
      ..._scope(bootstrap),
      'groupId': groupId,
      'date': date,
    };
    final body = await _client.getJson('/teacher/attendance', token: token, query: query);
    return TeacherAttendanceData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<ResultsTableData> fetchResultsTable({
    required String token,
    required TeacherBootstrap bootstrap,
    String? sessionId,
    String? examTypeId,
    String? subjectId,
    String? studentId,
  }) async {
    final query = _scope(bootstrap);
    if (sessionId != null && sessionId.isNotEmpty) query['sessionId'] = sessionId;
    if (examTypeId != null && examTypeId.isNotEmpty) query['examTypeId'] = examTypeId;
    if (subjectId != null && subjectId.isNotEmpty) query['subjectId'] = subjectId;
    if (studentId != null && studentId.isNotEmpty) query['studentId'] = studentId;
    final body = await _client.getJson('/teacher/marks/table', token: token, query: query);
    return ResultsTableData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<List<Map<String, dynamic>>> fetchMyAttendance({
    required String token,
    required TeacherBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/teacher/my-attendance', token: token, query: _scope(bootstrap));
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchMyPayroll({
    required String token,
    required TeacherBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/teacher/my-payroll', token: token, query: _scope(bootstrap));
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
