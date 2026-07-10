import '../../../core/api/authenticated_client.dart';
import '../../../core/api/portal_api.dart';
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
}
