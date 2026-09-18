import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/uploads/upload_errors.dart';
import 'package:mobile/features/uploads/upload_session_api.dart';

void main() {
  group('UploadSessionApi HTTP contract', () {
    test('create sends the M1 field names; 200-reuse surfaces created:false', () async {
      Map<String, dynamic>? seenBody;
      final api = UploadSessionApi(
        baseUrl: 'http://x',
        client: MockClient((request) async {
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({'success': true, 'created': false, 'data': _session()}), 200);
        }),
      );
      final result = await api.createSession(
        token: 'tok', purpose: 'document', fileName: 'a.pdf',
        mimeType: 'application/pdf', expectedSize: 10, idempotencyKey: 'k1');
      expect(seenBody, containsPair('originalFilename', 'a.pdf'));
      expect(seenBody, containsPair('idempotencyKey', 'k1'));
      expect(seenBody, containsPair('expectedSize', 10));
      expect(result.created, isFalse);
      expect(result.session.bytesUploaded, 0);
    });

    test('PATCH sends Upload-Offset + octet-stream + exact length', () async {
      final capture = _CaptureClient((request) => http.Response(
          jsonEncode({'success': true, 'data': {
            'bytesUploaded': 5, 'expectedSize': 10, 'partNumber': 1, 'complete': false}}),
          200));
      final api = UploadSessionApi(baseUrl: 'http://x', client: capture);
      final ack = await api.sendChunk(
          token: 'tok', sessionId: 's1', offset: 0, bytes: [1, 2, 3, 4, 5]);
      expect(capture.headers!['Upload-Offset'], '0');
      expect(capture.headers!['Content-Type'], 'application/octet-stream');
      expect(capture.contentLength, 5);
      expect(capture.headers!['Authorization'], 'Bearer tok');
      expect(capture.body, [1, 2, 3, 4, 5]);
      expect(ack.bytesUploaded, 5);
      expect(ack.complete, isFalse);
    });

    test('errors map to UploadApiException with status + Retry-After', () async {
      final api = UploadSessionApi(
        baseUrl: 'http://x',
        client: MockClient((request) async => http.Response(
              jsonEncode({'success': false, 'message': 'slow down'}),
              429,
              headers: {'retry-after': '4'},
            )),
      );
      try {
        await api.getSession(token: 'tok', sessionId: 's');
        fail('expected throw');
      } on UploadApiException catch (e) {
        expect(e.statusCode, 429);
        expect(e.retryAfterSeconds, 4);
        expect(e.message, 'slow down');
      }
    });

    test('complete returns fileRecordId; cancel hits DELETE', () async {
      String? seenMethod;
      String? seenPath;
      final api = UploadSessionApi(
        baseUrl: 'http://x',
        client: MockClient((request) async {
          seenMethod = request.method;
          seenPath = request.url.path;
          if (request.url.path.endsWith('/complete')) {
            return http.Response(
                jsonEncode({'success': true, 'created': true, 'data': {
                  ..._session(),
                  'status': 'COMPLETED',
                  'fileRecordId': 'file-1',
                  'fileUrl': '/api/uploads/file-1',
                }}),
                200);
          }
          return http.Response(
              jsonEncode({'success': true, 'data': {..._session(), 'status': 'CANCELLED'}}), 200);
        }),
      );
      final done = await api.completeSession(token: 'tok', sessionId: 's1');
      expect(seenPath, '/api/upload-sessions/s1/complete');
      expect(done.fileRecordId, 'file-1');
      expect(done.created, isTrue);
      await api.cancelSession(token: 'tok', sessionId: 's1');
      expect(seenMethod, 'DELETE');
    });
  });
}

Map<String, dynamic> _session() => {
      'id': 's1',
      'status': 'INITIATED',
      'expectedSize': 10,
      'bytesUploaded': 0,
      'fileRecordId': null,
      'fileUrl': null,
    };

/// Captures a live (un-finalized) request: MockClient pre-finalizes, so it
/// cannot observe streamed PATCH bodies.
class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.reply);

  final http.Response Function(http.BaseRequest request) reply;
  Map<String, String>? headers;
  List<int>? body;
  int? contentLength;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers = Map.of(request.headers);
    contentLength = request.contentLength;
    body = await request.finalize().toBytes();
    final res = reply(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(res.body)),
      res.statusCode,
      headers: res.headers,
    );
  }
}
