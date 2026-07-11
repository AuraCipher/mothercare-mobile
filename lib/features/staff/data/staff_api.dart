import '../../../core/api/authenticated_client.dart';
import '../../../core/api/portal_api.dart';
import '../models/staff_bootstrap.dart';

class StaffApi {
  StaffApi({AuthenticatedClient? client, PortalApi? portal})
      : _client = client ?? AuthenticatedClient(),
        _portal = portal ?? PortalApi();

  final AuthenticatedClient _client;
  final PortalApi _portal;

  Future<StaffBootstrap> fetchBootstrap({
    required String token,
    required String userName,
    required String role,
  }) async {
    final branch = await _portal.fetchPrimaryBranch(token: token);
    final academicYearId = await _portal.resolveAcademicYearId(
      token: token,
      branchId: branch.id,
    );
    final ay = await _portal.fetchAcademicYear(token: token, branchId: branch.id);
    return StaffBootstrap(
      academicYearId: academicYearId,
      academicYearLabel: ay.label,
      branchId: branch.id,
      branchName: branch.name,
      userName: userName,
      role: role,
    );
  }

  Future<Map<String, dynamic>> fetchProfile({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson(
      '/staff/profile',
      token: token,
      query: {'branchId': bootstrap.branchId},
    );
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  Map<String, String> _scope(StaffBootstrap bootstrap) => {
        'branchId': bootstrap.branchId,
        'academicYearId': bootstrap.academicYearId,
      };

  Future<Map<String, dynamic>> fetchCampusOverview({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/staff/campus/overview', token: token, query: _scope(bootstrap));
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> fetchCampusFees({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/staff/campus/fees', token: token, query: _scope(bootstrap));
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> fetchCampusStaff({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson(
      '/staff/campus/staff',
      token: token,
      query: {'branchId': bootstrap.branchId},
    );
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> fetchCampusAttendance({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/staff/campus/attendance', token: token, query: _scope(bootstrap));
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> fetchCampusResults({
    required String token,
    required StaffBootstrap bootstrap,
  }) async {
    final body = await _client.getJson('/staff/campus/results', token: token, query: _scope(bootstrap));
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
