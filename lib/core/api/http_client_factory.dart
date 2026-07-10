import 'package:http/http.dart' as http;

/// Allows E2E tests to substitute a mock HTTP client.
class HttpClientFactory {
  static http.Client Function()? testOverride;

  static http.Client create({http.Client? client}) {
    if (client != null) return client;
    return testOverride?.call() ?? http.Client();
  }
}
