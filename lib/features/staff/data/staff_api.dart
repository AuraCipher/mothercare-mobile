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
}
