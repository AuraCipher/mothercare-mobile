import '../api/authenticated_client.dart';

class ChatDeviceApi {
  ChatDeviceApi({AuthenticatedClient? client}) : _client = client ?? AuthenticatedClient();

  final AuthenticatedClient _client;

  Future<void> registerDevice({
    required String token,
    required String fcmToken,
    required String platform,
  }) async {
    await _client.postJson(
      '/chat/devices',
      token: token,
      body: {
        'token': fcmToken,
        'platform': platform,
      },
    );
  }

  Future<void> unregisterDevice({
    required String token,
    required String fcmToken,
  }) async {
    await _client.deleteJson(
      '/chat/devices',
      token: token,
      body: {'token': fcmToken},
    );
  }
}
