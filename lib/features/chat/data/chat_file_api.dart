import '../../../core/api/authenticated_client.dart';

/// Minimal FileRecord client for chat attachment housekeeping.
/// Only used to delete OUR OWN just-uploaded, never-sent files
/// (owner cleanup of orphans). Never deletes sent attachments.
class ChatFileApi {
  ChatFileApi({AuthenticatedClient? client, String? baseUrl})
      : _client = client ?? AuthenticatedClient(baseUrl: baseUrl);

  final AuthenticatedClient _client;

  Future<void> deleteFile({required String token, required String fileId}) async {
    await _client.deleteJson('/api/uploads/$fileId', token: token);
  }

  /// M5: processing-status + metadata read for send gating (READY check).
  /// Returns the raw record map (includes processingStatus when present).
  Future<Map<String, dynamic>> getFileMeta({required String token, required String fileId}) async {
    final body = await _client.getJson('/api/uploads/$fileId/meta', token: token);
    return body['data'] as Map<String, dynamic>? ?? {};
  }
}
