import '../../core/api/authenticated_client.dart';
import '../../core/models/portal_refs.dart';
import '../../core/storage/session_storage.dart';

class PortalApi {
  PortalApi({AuthenticatedClient? client, SessionStorage? storage})
      : _client = client ?? AuthenticatedClient(),
        _storage = storage ?? SessionStorage();

  final AuthenticatedClient _client;
  final SessionStorage _storage;

  Future<String> resolveAcademicYearId({
    required String token,
    String? branchId,
  }) async {
    final stored = await _storage.getAcademicYearId();
    if (stored != null && stored.isNotEmpty) return stored;

    final ay = await fetchAcademicYear(token: token, branchId: branchId);
    if (ay.id.isEmpty) {
      throw Exception('No active academic year');
    }
    return ay.id;
  }

  Future<AcademicYearRef> fetchAcademicYear({
    required String token,
    String? branchId,
  }) async {
    final query = <String, String>{};
    if (branchId != null && branchId.isNotEmpty) {
      query['branchId'] = branchId;
    }
    final body = await _client.getJson(
      '/me/academic-year',
      token: token,
      query: query.isEmpty ? null : query,
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final ay = AcademicYearRef.fromJson(data);
    if (ay.id.isNotEmpty) {
      await _storage.saveAcademicYearId(ay.id);
    }
    if (ay.branchId != null && ay.branchId!.isNotEmpty) {
      await _storage.saveActiveBranchId(ay.branchId!);
    }
    return ay;
  }

  Future<BranchRef> fetchPrimaryBranch({required String token}) async {
    final storedBranchId = await _storage.getActiveBranchId();
    final body = await _client.getJson('/me/branches', token: token);
    final rows = body['data'] as List<dynamic>? ?? [];
    if (rows.isEmpty) {
      throw Exception('No branch membership found');
    }

    if (storedBranchId != null) {
      for (final row in rows) {
        final branch = BranchRef.fromJson(row as Map<String, dynamic>);
        if (branch.id == storedBranchId) return branch;
      }
    }

    return BranchRef.fromJson(rows.first as Map<String, dynamic>);
  }
}
