import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api/http_client_factory.dart';

import '../../integration_test/support/e2e_http_mock.dart';
import '../../integration_test/support/mock_api_router.dart';

void main() {
  test('mock router returns room messages', () async {
    final mock = E2eHttpMock(MockApiRouter())..install();
    addTearDown(mock.uninstall);

    final client = HttpClientFactory.create();
    final res = await client.get(
      Uri.parse('http://10.0.2.2:5000/chat/rooms/room-school-ann/messages?limit=40'),
      headers: {'Authorization': 'Bearer test'},
    );

    expect(res.statusCode, 200);
    expect(res.body, contains('Welcome to the demo channel.'));
  });
}
