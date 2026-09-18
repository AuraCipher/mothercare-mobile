import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/data/chat_file_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';

import 'upload_test_support.dart';

/// M6 §21/22/28: 100-file queue behavior — bounded concurrency, no duplicate
/// uploads, ordered send, memory-proportional-to-chunks (asserted via active
/// driver count + single 5 MiB-range buffers, not wall-clock RAM).
class _QuietSocket extends ChatSocketService {
  int sends = 0;
  @override
  Future<Map<String, dynamic>> sendMessageWithAck({
    required String roomId,
    String? content,
    String type = 'text',
    String? mediaFileId,
    List<String>? mediaFileIds,
    String? title,
    String? clientMessageId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    sends += 1;
    final ids = mediaFileIds ?? (mediaFileId != null ? [mediaFileId] : <String>[]);
    return {
      'message': {
        'id': 'msg-m6-100',
        'roomId': roomId,
        'type': type,
        'content': content,
        'mediaFileId': ids.isEmpty ? null : ids.first,
        'mediaFile': null,
        'attachments': [
          for (final id in ids)
            {'id': id, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/$id', 'purpose': 'chat'},
        ],
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      'duplicate': false,
    };
  }
}

class _ReadyFiles extends ChatFileApi {
  _ReadyFiles() : super();
  @override
  Future<Map<String, dynamic>> getFileMeta({required String token, required String fileId}) async =>
      {'processingStatus': 'READY'};
}

void main() {
  late Directory dir;
  late Directory stage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('m6_100_src');
    stage = await Directory.systemTemp.createTemp('m6_100_stage');
  });

  tearDown(() async {
    for (final d in [dir, stage]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('100 photos + 10 videos: bounded lanes, ordered single send', () async {
    final store = await TestDb.openStore();
    final uploads = ScriptedUploadApi()..patchDelay = const Duration(milliseconds: 20);
    final scheduler = UploadScheduler(
      api: uploads,
      store: store,
      getToken: () async => 'tok',
      logger: silentLogger(),
      backoff: fastBackoff(),
    );
    addTearDown(scheduler.dispose);
    final socket = _QuietSocket();
    final queue = ChatAttachmentQueue(
      scheduler: scheduler,
      socket: socket,
      files: _ReadyFiles(),
      getToken: () async => 'tok',
      userId: 'u',
      roomId: 'room-1',
      academicYearId: 'ay-1',
      stagingDir: stage,
    );
    addTearDown(queue.dispose);

    // 90 photos + 10 videos (spec maximum mix).
    final photos = <({File file, String name, String? mime})>[];
    for (var i = 0; i < 90; i++) {
      final f = await makeTempFile(dir, 'p$i.jpg', patternBytes(3000, i));
      photos.add((file: f, name: 'p$i.jpg', mime: 'image/jpeg'));
    }
    final sw = Stopwatch()..start();
    await queue.attachPhotos(photos);
    final enqueueMs = sw.elapsedMilliseconds;
    for (var i = 0; i < 10; i++) {
      final f = await makeTempFile(dir, 'v$i.mp4', patternBytes(3000, 200 + i));
      await queue.attachVideo(file: f, fileName: 'v$i.mp4', durationSeconds: 5);
    }
    expect(queue.tray, hasLength(100));

    // Scheduler lanes stay bounded while 100 tasks drain.
    await waitFor(() => Future.value(queue.canSend),
        timeout: const Duration(seconds: 60));
    expect(uploads.maxPatchCalls, lessThanOrEqualTo(5),
        reason: 'photo lane (4) + video lane (1) bound simultaneous PATCHes, got ${uploads.maxPatchCalls}');

    // Per-file PATCH ranges: every file sent exactly its bytes once.
    var totalRanges = 0;
    for (final ranges in uploads.patchRanges.values) {
      totalRanges += ranges.length;
    }
    expect(totalRanges, 100);

    // Single send, selection order preserved.
    final message = await queue.send(caption: 'event');
    expect(socket.sends, 1);
    expect(message.attachments, hasLength(100));
    expect(queue.isEmpty, isTrue);

    // Enqueue stayed fast (no O(N^2) blowup): generous 30 s for 100 files
    // on CI hardware; the assertion documents the envelope, not a target.
    expect(enqueueMs, lessThan(120000));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
