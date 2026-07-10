import '../../../core/api/portal_api.dart';
import '../../../core/storage/session_storage.dart';
import '../models/staff_bootstrap.dart';

class StaffApi {
  StaffApi({PortalApi? portal, SessionStorage? storage})
      : _portal = portal ?? PortalApi(),
        _storage = storage ?? SessionStorage();

  final PortalApi _portal;
  final SessionStorage _storage;

  Future<StaffBootstrap> fetchBootstrap({
    required String token,
    required String userName,
    required String role,
  }) async {
    final ay = await _portal.fetchAcademicYear(token: token);
    final branch = await _portal.fetchPrimaryBranch(token: token);
    await _storage.saveAcademicYearId(ay.id);
    return StaffBootstrap(
      academicYearId: ay.id,
      academicYearLabel: ay.label,
      branchId: branch.id,
      branchName: branch.name,
      userName: userName,
      role: branch.role ?? role,
    );
  }
}
