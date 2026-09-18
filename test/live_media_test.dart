import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/data/chat_file_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/send_intent_store.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';
import 'package:mobile/features/uploads/upload_session_api.dart';

import 'upload_test_support.dart';

/// Hand-crafted minimal MP4 (ftyp + moov(mvhd + trak(tkhd + mdia(mdhd + hdlr)))),
/// mirroring backend/tests/modules/media/fixtures.ts. Duration via mvhd.
Uint8List mp4Seconds(int seconds, {String handler = 'vide'}) {
  List<int> box(String type, List<int> payload) {
    final size = 8 + payload.length;
    return [
      (size >> 24) & 0xFF, (size >> 16) & 0xFF, (size >> 8) & 0xFF, size & 0xFF,
      ...type.codeUnits,
      ...payload,
    ];
  }

  final timescale = 1000;
  final duration = seconds * timescale;
  List<int> u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  final ftyp = box('ftyp', [...'isom'.codeUnits, 0, 0, 0, 0, ...'isom'.codeUnits, ...'mp42'.codeUnits]);
  final mvhd = box('mvhd', [...List<int>.filled(12, 0), ...u32(timescale), ...u32(duration), ...List<int>.filled(76, 0)]);
  final mdhd = box('mdhd', [...List<int>.filled(12, 0), ...u32(timescale), ...u32(duration), ...List<int>.filled(8, 0)]);
  final hdlr = box('hdlr', [...List<int>.filled(8, 0), ...handler.codeUnits, ...List<int>.filled(12, 0)]);
  final mdia = box('mdia', [...mdhd, ...hdlr]);
  final tkhdBody = List<int>.filled(92, 0)..[3] = 7;
  final trak = box('trak', [...box('tkhd', tkhdBody), ...mdia]);
  final moov = box('moov', [...mvhd, ...trak]);
  return Uint8List.fromList([...ftyp, ...moov]);
}

/// Opt-in live M5 test: queue → M3 engine → real sessions → FileRecords →
/// inline media processing (no Redis here) → READY gating → socket send →
/// history → uncertain-reconcile → conflict probe.
///
/// Runs ONLY with:
///   M5_LIVE_BACKEND=1 M5_API_URL=http://127.0.0.1:5000 M5_TOKEN=`<jwt>`
///   M5_ROOM_ID=m5-room M5_AY_ID=m5-ay
/// plus `--dart-define=API_BASE_URL=http://127.0.0.1:5000`.
/// Fixture rows are created out-of-band (see m5-report). Skipped in CI.
void main() {
  final enabled = Platform.environment['M5_LIVE_BACKEND'] == '1';
  final baseUrl = Platform.environment['M5_API_URL'] ?? 'http://127.0.0.1:5000';
  final token = Platform.environment['M5_TOKEN'] ?? '';
  final roomId = Platform.environment['M5_ROOM_ID'] ?? 'm5-room';
  final ayId = Platform.environment['M5_AY_ID'] ?? 'm5-ay';

  test('live video upload → probed READY → send → history → reconcile', () async {
    if (!enabled || token.isEmpty) {
      markTestSkipped('Set M5_LIVE_BACKEND=1 M5_API_URL=... M5_TOKEN=... M5_ROOM_ID=... to run.');
      return;
    }
    // In-memory app database so send-intent rows persist in-test
    // (flutter test has no path_provider channels for the real one).
    await TestDb.openStore();
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

    final stage = await Directory.systemTemp.createTemp('m5_live_stage');
    addTearDown(() => stage.delete(recursive: true));
    final queue = ChatAttachmentQueue(
      scheduler: scheduler,
      socket: socket,
      files: ChatFileApi(baseUrl: baseUrl),
      getToken: () async => token,
      userId: 'm5-live-user',
      roomId: roomId,
      academicYearId: ayId,
      stagingDir: stage,
    );
    addTearDown(queue.dispose);

    final dir = await Directory.systemTemp.createTemp('m5_live_src');
    addTearDown(() => dir.delete(recursive: true));
    final videoBytes = mp4Seconds(5);
    final videoFile = File('${dir.path}/live.mp4');
    await videoFile.writeAsBytes(videoBytes, flush: true);
    await queue.attachVideo(file: videoFile, fileName: 'live.mp4', durationSeconds: 5);
    await waitFor(() => Future.value(queue.canSend),
        timeout: const Duration(minutes: 2));
    final taskId = queue.tray.single.item.taskId;
    final task = (await store.getTask('m5-live-user', taskId))!;
    expect(task.fileRecordId, isNotNull);

    // Processing ran (inline fallback, no Redis): meta must show READY +
    // probed duration before the send is allowed through.
    final meta = await ChatFileApi(baseUrl: baseUrl)
        .getFileMeta(token: token, fileId: task.fileRecordId!);
    expect(meta['processingStatus'], 'READY');
    expect((meta['metadata'] as Map)['probedDurationSeconds'], closeTo(5, 0.5));

    final caption = 'm5-live-${DateTime.now().millisecondsSinceEpoch}';
    final message =
        await queue.send(caption: caption).timeout(const Duration(seconds: 120));
    expect(message.attachments, hasLength(1));

    final api = ChatApi();
    final history = await api.fetchMessages(token: token, roomId: roomId, limit: 10);
    final found = history.where((m) => m.id == message.id).toList();
    expect(found, hasLength(1));
    expect(found.single.attachments.map((a) => a.id).toList(),
        [task.fileRecordId]);

    // Uncertain-timeout retry with the same key converges (server dedupe).
    final dupKey = 'm5-live-dup-${DateTime.now().millisecondsSinceEpoch}';
    final first = await socket.sendMessageWithAck(
      roomId: roomId, content: 'dup-probe', type: 'text', clientMessageId: dupKey,
    );
    final second = await socket.sendMessageWithAck(
      roomId: roomId, content: 'dup-probe', type: 'text', clientMessageId: dupKey,
    );
    expect((first['message'] as Map)['id'], (second['message'] as Map)['id']);
    expect(second['duplicate'], isTrue);

    // Same key, different payload → deterministic conflict (no merge).
    try {
      await socket.sendMessageWithAck(
        roomId: roomId, content: 'DIFFERENT', type: 'text', clientMessageId: dupKey,
      );
      fail('expected conflict rejection');
    } catch (e) {
      expect(e.toString(), contains('different content'));
    }

    // Cleanup (dev DB only): soft-delete our messages.
    for (final id in [message.id, (first['message'] as Map)['id'] as String]) {
      try {
        await api.deleteMessage(token: token, messageId: id);
      } catch (_) {}
    }
    // Send-intent rows for this room must be gone after confirmed sends.
    expect(await SendIntentStore().listRoomIntents('m5-live-user', roomId), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
