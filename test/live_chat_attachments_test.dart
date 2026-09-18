import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/data/chat_file_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/chat_upload_pool.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';
import 'package:mobile/features/uploads/upload_session_api.dart';

import 'upload_test_support.dart';

/// Opt-in live M4 test: Flutter queue → M3 engine → real UploadSession →
/// real FileRecords → real Socket.IO send → real history read.
///
/// Runs ONLY with:
///   M4_LIVE_BACKEND=1 M4_API_URL=http://127.0.0.1:5000 M4_TOKEN=`<jwt>`
///   M4_ROOM_ID=m4-room M4_AY_ID=m4-ay
/// plus `--dart-define=API_BASE_URL=http://127.0.0.1:5000` so the default
/// AppConfig-based clients (ChatApi) hit the same host.
/// (fixture rows created out-of-band; see m4-report. Skipped in normal CI.)
void main() {
  final enabled = Platform.environment['M4_LIVE_BACKEND'] == '1';
  final baseUrl = Platform.environment['M4_API_URL'] ?? 'http://127.0.0.1:5000';
  final token = Platform.environment['M4_TOKEN'] ?? '';
  final roomId = Platform.environment['M4_ROOM_ID'] ?? 'm4-room';
  final ayId = Platform.environment['M4_AY_ID'] ?? 'm4-ay';

  test('live multi-attachment chat send', () async {
    if (!enabled || token.isEmpty) {
      markTestSkipped('Set M4_LIVE_BACKEND=1 M4_API_URL=... M4_TOKEN=... M4_ROOM_ID=... to run.');
      return;
    }
    final store = await TestDb.openStore();
    final scheduler = UploadScheduler(
      api: UploadSessionApi(baseUrl: baseUrl),
      store: store,
      getToken: () async => token,
    );
    addTearDown(scheduler.dispose);

    final socket = ChatSocketService();
    socket.connect(token: token, academicYearId: ayId, baseUrl: baseUrl);
    addTearDown(socket.dispose);
    await Future.delayed(const Duration(seconds: 2));
    socket.joinRoom(roomId);

    final stage = await Directory.systemTemp.createTemp('m4_live_stage');
    addTearDown(() => stage.delete(recursive: true));
    final queue = ChatAttachmentQueue(
      scheduler: scheduler,
      socket: socket,
      files: ChatFileApi(baseUrl: baseUrl),
      getToken: () async => token,
      userId: 'm4-live-user',
      roomId: roomId,
      academicYearId: ayId,
      stagingDir: stage,
    );
    addTearDown(queue.dispose);

    final dir = await Directory.systemTemp.createTemp('m4_live_src');
    addTearDown(() => dir.delete(recursive: true));
    // Small pdfs (extension-fallback allowlist; synthetic bytes).
    final f1 = await makeTempFile(dir, 'live1.pdf', patternBytes(3000, 1));
    final f2 = await makeTempFile(dir, 'live2.pdf', patternBytes(4000, 2));
    await queue.attachPhotos([
      (file: f1, name: 'live1.pdf', mime: 'application/pdf'),
      (file: f2, name: 'live2.pdf', mime: 'application/pdf'),
    ]);
    await waitFor(() => Future.value(queue.canSend),
        timeout: const Duration(minutes: 2));

    final caption = 'm4-live-${DateTime.now().millisecondsSinceEpoch}';
    final message = await queue
        .send(caption: caption)
        .timeout(const Duration(seconds: 60));
    expect(message.attachments, hasLength(2));
    expect(message.content, caption);

    // History serves the attachments in order.
    final api = ChatApi();
    final history = await api.fetchMessages(token: token, roomId: roomId, limit: 10);
    final found = history.where((m) => m.id == message.id).toList();
    expect(found, hasLength(1));
    expect(found.single.attachments.map((a) => a.id).toList(),
        message.attachments.map((a) => a.id).toList());

    // Same clientMessageId twice → single logical message (server dedupe).
    final dupKey = 'm4-live-dup-${DateTime.now().millisecondsSinceEpoch}';
    final first = await socket.sendMessageWithAck(
      roomId: roomId, content: 'dup-probe', type: 'text', clientMessageId: dupKey,
    );
    final second = await socket.sendMessageWithAck(
      roomId: roomId, content: 'dup-probe', type: 'text', clientMessageId: dupKey,
    );
    expect((first['message'] as Map)['id'], (second['message'] as Map)['id']);
    expect(second['duplicate'], isTrue);

    // Best-effort cleanup (dev DB only): soft-delete our messages.
    for (final id in [message.id, (first['message'] as Map)['id'] as String]) {
      try {
        await api.deleteMessage(token: token, messageId: id);
      } catch (_) {}
    }
    await ChatUploadPool.releaseAll();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
