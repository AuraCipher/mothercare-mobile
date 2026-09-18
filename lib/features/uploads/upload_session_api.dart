import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/api/http_client_factory.dart';
import 'upload_errors.dart';

/// Server view of an UploadSession (subset the client is allowed to see).
class RemoteUploadSession {
  RemoteUploadSession({
    required this.id,
    required this.status,
    required this.expectedSize,
    required this.bytesUploaded,
    this.fileRecordId,
    this.fileUrl,
  });

  final String id;
  final String status;
  final int expectedSize;
  final int bytesUploaded;
  final String? fileRecordId;
  final String? fileUrl;

  bool get isCompleted => status == 'COMPLETED';
  bool get isTerminal =>
      status == 'COMPLETED' ||
      status == 'CANCELLED' ||
      status == 'EXPIRED' ||
      status == 'FAILED';

  static RemoteUploadSession fromJson(Map<String, dynamic> json) => RemoteUploadSession(
        id: json['id'] as String,
        status: json['status'] as String,
        expectedSize: json['expectedSize'] as int,
        bytesUploaded: (json['bytesUploaded'] as int?) ?? 0,
        fileRecordId: json['fileRecordId'] as String?,
        fileUrl: json['fileUrl'] as String?,
      );
}

class ChunkAck {
  ChunkAck({
    required this.bytesUploaded,
    required this.expectedSize,
    required this.partNumber,
    required this.complete,
  });

  final int bytesUploaded;
  final int expectedSize;
  final int partNumber;
  final bool complete;

  static ChunkAck fromJson(Map<String, dynamic> json) => ChunkAck(
        bytesUploaded: json['bytesUploaded'] as int,
        expectedSize: json['expectedSize'] as int,
        partNumber: (json['partNumber'] as int?) ?? 0,
        complete: (json['complete'] as bool?) ?? false,
      );
}

/// Thin HTTP client for the M1/M2 resumable protocol. No retry, no state —
/// the engine owns recovery. JSON calls reuse project timeout conventions
/// (10 s); chunk PATCH gets a longer budget (90 s) that intentionally
/// exceeds the server's 60 s request timeout, so the server's verdict
/// (success or close) normally arrives before the client gives up — and
/// either way the engine reconciles via GET.
class UploadSessionApi {
  UploadSessionApi({http.Client? client, String? baseUrl, this.chunkTimeout = const Duration(seconds: 90)})
      : _client = HttpClientFactory.create(client: client),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration chunkTimeout;

  static const String chunkContentType = 'application/octet-stream';

  Map<String, String> _auth(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Future<({RemoteUploadSession session, bool created})> createSession({
    required String token,
    required String purpose,
    required String fileName,
    required String mimeType,
    required int expectedSize,
    required String idempotencyKey,
    String? entityType,
    String? entityId,
    String? roomId,
    String? academicYearId,
    Map<String, dynamic>? metadata,
  }) async {
    final body = <String, dynamic>{
      'purpose': purpose,
      'originalFilename': fileName,
      'mimeType': mimeType,
      'expectedSize': expectedSize,
      'idempotencyKey': idempotencyKey,
      'entityType': ?entityType,
      'entityId': ?entityId,
      'roomId': ?roomId,
      'academicYearId': ?academicYearId,
      'metadata': ?metadata,
    };
    final res = await _send(() => _client
        .post(Uri.parse('$_baseUrl/api/upload-sessions'),
            headers: {..._auth(token), 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 10)));
    final data = _data(res);
    return (
      session: RemoteUploadSession.fromJson(data['data'] as Map<String, dynamic>),
      created: (data['created'] as bool?) ?? true,
    );
  }

  Future<RemoteUploadSession> getSession({required String token, required String sessionId}) async {
    final res = await _send(() => _client
        .get(Uri.parse('$_baseUrl/api/upload-sessions/$sessionId'), headers: _auth(token))
        .timeout(const Duration(seconds: 10)));
    return RemoteUploadSession.fromJson(_data(res)['data'] as Map<String, dynamic>);
  }

  /// Sends exactly [bytes] at [offset]. The caller owns file I/O; this method
  /// owns only the HTTP exchange. [onCancel] is polled cooperatively —
  /// package:http cannot abort a socket, so cancellation means "stop waiting
  /// and ignore the outcome"; the engine reconciles via GET afterwards.
  Future<ChunkAck> sendChunk({
    required String token,
    required String sessionId,
    required int offset,
    required List<int> bytes,
    bool Function()? onCancel,
  }) async {
    final request = http.StreamedRequest('PATCH', Uri.parse('$_baseUrl/api/upload-sessions/$sessionId'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = chunkContentType;
    request.headers['Upload-Offset'] = '$offset';
    request.contentLength = bytes.length;
    // Bounded: callers never pass more than one 5 MiB protocol chunk.
    request.sink.add(bytes);
    unawaited(request.sink.close());
    final streamed = await _send(() => _client.send(request).timeout(chunkTimeout));
    final res = await http.Response.fromStream(streamed);
    if (onCancel != null && onCancel()) {
      throw UploadChunkCancelled();
    }
    return ChunkAck.fromJson(_dataRes(res)['data'] as Map<String, dynamic>);
  }

  Future<({RemoteUploadSession session, bool created, String? fileRecordId})> completeSession({
    required String token,
    required String sessionId,
  }) async {
    final res = await _send(() => _client
        .post(Uri.parse('$_baseUrl/api/upload-sessions/$sessionId/complete'),
            headers: _auth(token))
        .timeout(const Duration(seconds: 30)));
    final data = _data(res);
    final session =
        RemoteUploadSession.fromJson(data['data'] as Map<String, dynamic>);
    return (
      session: session,
      created: (data['created'] as bool?) ?? true,
      fileRecordId: (data['data'] as Map<String, dynamic>)['fileRecordId'] as String?,
    );
  }

  Future<RemoteUploadSession> cancelSession({required String token, required String sessionId}) async {
    final res = await _send(() => _client
        .delete(Uri.parse('$_baseUrl/api/upload-sessions/$sessionId'), headers: _auth(token))
        .timeout(const Duration(seconds: 10)));
    return RemoteUploadSession.fromJson(_data(res)['data'] as Map<String, dynamic>);
  }

  /// Lets transport errors (Socket/Timeout) propagate untouched for the
  /// classifier; only wraps send-scheduling failures (should not happen).
  Future<T> _send<T>(Future<T> Function() fn) => fn();

  Map<String, dynamic> _data(http.Response res) => _dataRes(res);

  Map<String, dynamic> _dataRes(http.Response res) {
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw UploadApiException(
        res.statusCode >= 500 ? 'Server error. Try again later.' : 'Unexpected response from server',
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body['success'] == false) {
        throw UploadApiException(body['message'] as String? ?? 'Request failed',
            statusCode: res.statusCode);
      }
      return body;
    }
    throw UploadApiException(
      body['message'] as String? ?? 'Request failed (${res.statusCode})',
      statusCode: res.statusCode,
      retryAfterSeconds: parseRetryAfterSeconds(res.headers['retry-after']),
    );
  }
}

/// Chunk result arrived after local cancellation — ignored by design.
/// The engine reconciles via GET (or DELETE) afterwards; never classified
/// as a transport error.
class UploadChunkCancelled implements Exception {
  @override
  String toString() => 'Chunk completed after cancellation; outcome ignored.';
}
