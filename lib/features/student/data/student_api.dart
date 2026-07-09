import '../../../core/api/authenticated_client.dart';
import '../models/student_bootstrap.dart';

class StudentApi {
  StudentApi({AuthenticatedClient? client}) : _client = client ?? AuthenticatedClient();

  final AuthenticatedClient _client;

  Future<StudentBootstrap> fetchBootstrap({required String token}) async {
    final body = await _client.getJson('/student/bootstrap', token: token);
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return StudentBootstrap.fromJson(data);
  }
}
