import '../../../core/api/authenticated_client.dart';
import '../models/chat_models.dart';

class ChatApi {
  ChatApi({AuthenticatedClient? client}) : _client = client ?? AuthenticatedClient();

  final AuthenticatedClient _client;

  Future<ChatLandingData> fetchStudentLanding({required String token}) async {
    final body = await _client.getJson('/student/chat/landing', token: token);
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatLandingData.fromJson(data);
  }

  Future<ChatLandingData> fetchStaffLanding({
    required String token,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/chat/rooms',
      token: token,
      query: {'academicYearId': academicYearId},
    );
    final roomsRaw = body['data'] as List<dynamic>? ?? [];
    final rooms = roomsRaw
        .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return ChatLandingData(
      sections: groupRoomsForStaffLanding(rooms),
      rooms: rooms,
    );
  }

  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String roomId,
    String? cursor,
    int limit = 40,
  }) async {
    final body = await _client.getJson(
      '/chat/rooms/$roomId/messages',
      token: token,
      query: {
        'cursor': ?cursor,
        'limit': '$limit',
      },
    );
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }
}
