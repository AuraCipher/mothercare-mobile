import '../../../core/api/api_exception.dart';
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

  Future<ChatLandingData> fetchTeacherLanding({
    required String token,
    required String branchId,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/teacher/chat/landing',
      token: token,
      query: {
        'branchId': branchId,
        'academicYearId': academicYearId,
      },
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatLandingData.fromJson(data);
  }

  Future<ChatRoomSummary> openTeacherDirectMessage({
    required String token,
    required String branchId,
    required String academicYearId,
    required String participantUserId,
    required String contactName,
  }) async {
    final body = await _client.postJson(
      '/teacher/chat/dm',
      token: token,
      query: {
        'branchId': branchId,
        'academicYearId': academicYearId,
      },
      body: {'participantUserId': participantUserId},
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatRoomSummary(
      id: data['roomId'] as String? ?? '',
      kind: 'direct_message',
      name: contactName,
      canPost: true,
      unreadCount: 0,
    );
  }

  Future<ChatRoomSummary> openStudentDirectMessage({
    required String token,
    required String participantUserId,
    required String contactName,
  }) async {
    final body = await _client.postJson(
      '/student/chat/dm',
      token: token,
      body: {'participantUserId': participantUserId},
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatRoomSummary(
      id: data['roomId'] as String? ?? '',
      kind: 'direct_message',
      name: contactName,
      canPost: true,
      unreadCount: 0,
    );
  }

  Future<ChatLandingData> fetchAdminLanding({
    required String token,
    required String branchId,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/staff/chat/landing',
      token: token,
      query: {
        'branchId': branchId,
        'academicYearId': academicYearId,
      },
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatLandingData.fromJson(data);
  }

  Future<ChatRoomSummary> openDirectMessage({
    required String token,
    required String branchId,
    required String academicYearId,
    required String participantUserId,
    required String contactName,
  }) async {
    final body = await _client.postJson(
      '/staff/chat/dm',
      token: token,
      body: {
        'branchId': branchId,
        'academicYearId': academicYearId,
        'participantUserId': participantUserId,
      },
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return ChatRoomSummary(
      id: data['roomId'] as String? ?? '',
      kind: 'direct_message',
      name: contactName,
      canPost: true,
      unreadCount: 0,
    );
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

  Future<void> deleteMessage({
    required String token,
    required String messageId,
  }) async {
    await _client.deleteJson('/chat/messages/$messageId', token: token);
  }

  /// M5: send-intent reconciliation — did (roomId, clientMessageId) land?
  /// Returns null on 404 (not sent); throws otherwise.
  Future<ChatMessage?> fetchMessageByClientKey({
    required String token,
    required String roomId,
    required String clientMessageId,
  }) async {
    try {
      final body = await _client.getJson(
        '/chat/rooms/$roomId/messages/by-client-key',
        token: token,
        query: {'clientMessageId': clientMessageId},
      );
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      return ChatMessage.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ChatMessage> updateMessage({
    required String token,
    required String messageId,
    required String content,
  }) async {
    final body = await _client.patchJson(
      '/chat/messages/$messageId',
      token: token,
      body: {'content': content},
    );
    return ChatMessage.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<ContactPickerData> fetchStudentContacts({required String token}) async {
    final body = await _client.getJson('/student/chat/contacts', token: token);
    return ContactPickerData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<ContactPickerData> fetchTeacherContacts({
    required String token,
    required String branchId,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/teacher/chat/contacts',
      token: token,
      query: {'branchId': branchId, 'academicYearId': academicYearId},
    );
    return ContactPickerData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }

  Future<ContactPickerData> fetchAdminContacts({
    required String token,
    required String branchId,
    required String academicYearId,
  }) async {
    final body = await _client.getJson(
      '/staff/chat/contacts',
      token: token,
      query: {'branchId': branchId, 'academicYearId': academicYearId},
    );
    return ContactPickerData.fromJson(body['data'] as Map<String, dynamic>? ?? {});
  }
}
