import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/api/http_client_factory.dart';

import 'mock_api_router.dart';

/// Installs a mock `http.Client` for offline E2E runs.
class E2eHttpMock {
  E2eHttpMock(this.router);

  final MockApiRouter router;
  MockClient? _client;

  void install() {
    _client = MockClient((request) async {
      final routed = router.route(
        request.method,
        request.url,
        request.body.isEmpty ? null : request.body,
      );
      return http.Response(
        routed.body,
        routed.status,
        headers: routed.headers,
      );
    });
    HttpClientFactory.testOverride = () => _client!;
  }

  void uninstall() {
    HttpClientFactory.testOverride = null;
    _client?.close();
    _client = null;
  }
}
