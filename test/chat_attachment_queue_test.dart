import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/data/chat_file_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';
import 'package:mobile/features/uploads/upload_task.dart';
import 'package:mobile/features/uploads/upload_task_store.dart';

import 'upload_test_support.dart';

class FakeSocket extends ChatSocketService {
  final sent = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> byClientKey = {};
  bool failUncertainOnce = false;

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
    final key = clientMessageId ?? 'no-key-${sent.length}';
    final payload = {
      'roomId': roomId, 'type': type, 'content': content,
      'mediaFileId': mediaFileId, 'mediaFileIds': mediaFileIds,
      'clientMessageId': key,
    };
    sent.add(payload);
    if (failUncertainOnce) {
      failUncertainOnce = false;
      // Server committed, response lost: record the message, then time out.
      byClientKey[key] = _envelope(key, payload);
      throw ChatSendException('Send timed out.', uncertain: true);
    }
    if (byClientKey.containsKey(key)) {
      return {'message': byClientKey[key]!, 'duplicate': true};
    }
    final envelope = _envelope(key, payload);
    byClientKey[key] = envelope;
    return {'message': envelope, 'duplicate': false};
  }

  Map<String, dynamic> _envelope(String key, Map<String, dynamic> payload) {
    final ids = ((payload['mediaFileIds'] as List?)?.cast<String>()) ??
        (payload['mediaFileId'] != null ? [payload['mediaFileId'] as String] : <String>[]);
    return {
      'id': 'msg-$key',
      'roomId': payload['roomId'],
      'type': payload['type'],
      'content': payload['content'],
      'mediaFileId': ids.isEmpty ? null : ids.first,
      'mediaFile': ids.isEmpty
          ? null
          : {'id': ids.first, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/${ids.first}', 'purpose': 'chat'},
      'attachments': [
        for (final id in ids)
          {'id': id, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/$id', 'purpose': 'chat'},
      ],
      'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class FakeFiles extends ChatFileApi {
  FakeFiles() : super();
  final deleted = <String>[];
  @override
  Future<void> deleteFile({required String token, required String fileId}) async {
    deleted.add(fileId);
  }

  @override
  Future<Map<String, dynamic>> getFileMeta({required String token, required String fileId}) async {
    return {'processingStatus': 'READY'};
  }
}

({UploadScheduler scheduler, FakeSocket socket, FakeFiles files, ChatAttachmentQueue queue})
    makeQueue(ScriptedUploadApi api, UploadTaskStore store, Directory stage,
        {String userId = 'u', String roomId = 'room-1'}) {
  final scheduler = UploadScheduler(
      api: api,
      store: store,
      getToken: () async => 'tok',
      logger: silentLogger(),
      backoff: fastBackoff());
  final socket = FakeSocket();
  final files = FakeFiles();
  final queue = ChatAttachmentQueue(
    scheduler: scheduler,
    socket: socket,
    files: files,
    getToken: () async => 'tok',
    userId: userId,
    roomId: roomId,
    academicYearId: 'ay-1',
    stagingDir: stage,
  );
  return (scheduler: scheduler, socket: socket, files: files, queue: queue);
}

void main() {
  late Directory dir;
  late Directory stage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('m4_queue_src');
    stage = await Directory.systemTemp.createTemp('m4_queue_stage');
  });

  tearDown(() async {
    for (final d in [dir, stage]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('selection limits', () {
    test('100 media ok, 101st rejected; 10 videos ok, 11th rejected', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final q = ctx.queue;
      for (var i = 0; i < 90; i++) {
        final f = await makeTempFile(dir, 'p$i.jpg', patternBytes(10, i));
        await q.attachPhotos([(file: f, name: 'p$i.jpg', mime: 'image/jpeg')]);
      }
      for (var i = 0; i < 10; i++) {
        final f = await makeTempFile(dir, 'v$i.mp4', patternBytes(10, 100 + i));
        await q.attachVideo(file: f, fileName: 'v$i.mp4', durationSeconds: 5);
      }
      expect(q.tray, hasLength(100));
      final extra = await makeTempFile(dir, 'x.jpg', patternBytes(10, 1));
      await expectLater(
          q.attachPhotos([(file: extra, name: 'x.jpg', mime: 'image/jpeg')]),
          throwsA(isA<AttachmentLimitException>()));
      final extraV = await makeTempFile(dir, 'x.mp4', patternBytes(10, 2));
      await expectLater(q.attachVideo(file: extraV, fileName: 'x.mp4', durationSeconds: 5),
          throwsA(isA<AttachmentLimitException>()));
      expect(q.tray, hasLength(100));
    });

    test('bulk attach preserves selection order indexes', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final q = ctx.queue;
      final photos = <({File file, String name, String? mime})>[];
      for (var i = 0; i < 5; i++) {
        final f = await makeTempFile(dir, 'b$i.jpg', patternBytes(10, i));
        photos.add((file: f, name: 'b$i.jpg', mime: 'image/jpeg'));
      }
      await q.attachPhotos(photos);
      expect(q.tray.map((e) => e.item.sortIndex).toList(), [0, 1, 2, 3, 4]);
      expect(q.tray.map((e) => e.item.fileName).toList(),
          ['b0.jpg', 'b1.jpg', 'b2.jpg', 'b3.jpg', 'b4.jpg']);
    });
  });

  group('send gating + ordering + partial failure', () {
    test('send disabled while uploading; enabled when settled with completions', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..patchDelay = const Duration(milliseconds: 80);
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 's.jpg', patternBytes(6000, 1));
      await ctx.queue.attachPhotos([(file: f, name: 's.jpg', mime: 'image/jpeg')]);
      expect(ctx.queue.canSend, isFalse);
      await waitFor(() async =>
          (await store.getTask('u', ctx.queue.tray.single.item.taskId))?.state ==
          UploadTaskState.completed);
      expect(ctx.queue.canSend, isTrue);
    });

    test('multi-attachment send uses selection order', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final files = <File>[];
      for (var i = 0; i < 3; i++) {
        files.add(await makeTempFile(dir, 'o$i.jpg', patternBytes(100, i)));
      }
      await ctx.queue.attachPhotos([
        for (var i = 0; i < 3; i++) (file: files[i], name: 'o$i.jpg', mime: 'image/jpeg'),
      ]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final message = await ctx.queue.send(caption: 'trip');
      expect(message.content, 'trip');
      final sentIds = (ctx.socket.sent.single['mediaFileIds'] as List).cast<String>();
      expect(sentIds, hasLength(3));
      final tasks = await store.listUserTasks('u');
      expect(tasks, isEmpty, reason: 'sent attachments leave the tray');
      expect(message.attachments.map((a) => a.id).toList(), sentIds);
      expect(message.mediaFile?.id, sentIds.first);
    });

    test('failed file isolated: send remaining, then heal and retry failure', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..failPatchWith = 500;
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final q = ctx.queue;
      final okF = await makeTempFile(dir, 'ok.jpg', patternBytes(100, 1));
      final badF = await makeTempFile(dir, 'bad.jpg', patternBytes(100, 2));
      await q.attachPhotos([(file: okF, name: 'ok.jpg', mime: 'image/jpeg')]);
      await q.attachPhotos([(file: badF, name: 'bad.jpg', mime: 'image/jpeg')]);
      // Both exhaust the fast budget and park as failed.
      await waitFor(() async =>
          (await store.listUserTasks('u')).every((t) => t.state == UploadTaskState.failed));
      // Heal and retry only the first: it completes while the other stays failed.
      api.failPatchWith = 0;
      await q.retryAttachment(q.tray[0].item.taskId);
      await waitFor(() => Future.value(q.canSend));
      expect(q.completedTasks, hasLength(1));
      final message = await q.send();
      expect(message.attachments, hasLength(1));
      expect(q.tray, hasLength(1), reason: 'failed file stays for explicit retry/remove');
      // Heal the failure too.
      await q.retryAttachment(q.tray.single.item.taskId);
      await waitFor(() => Future.value(q.canSend));
      final message2 = await q.send();
      expect(message2.attachments, hasLength(1));
      expect(q.isEmpty, isTrue);
    });
  });

  group('remove semantics', () {
    test('completed-unsent removal deletes the server file; failed removal just drops', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 'r.jpg', patternBytes(100, 1));
      await ctx.queue.attachPhotos([(file: f, name: 'r.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final taskId = ctx.queue.tray.single.item.taskId;
      final fileRecordId = (await store.getTask('u', taskId))!.fileRecordId!;
      await ctx.queue.removeAttachment(taskId);
      expect(ctx.files.deleted, [fileRecordId]);
      expect(await store.getTask('u', taskId), isNull);
      expect(ctx.queue.isEmpty, isTrue);
    });
  });

  group('idempotent send retry', () {
    test('uncertain timeout retries with the SAME clientMessageId', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 'u.jpg', patternBytes(100, 1));
      await ctx.queue.attachPhotos([(file: f, name: 'u.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      ctx.socket.failUncertainOnce = true;
      await expectLater(ctx.queue.send(), throwsA(isA<ChatSendException>()));
      expect(ctx.queue.pendingSend?.uncertain, isTrue);
      final key = ctx.queue.pendingSend!.clientMessageId;
      final message = await ctx.queue.retrySend();
      expect(ctx.socket.sent.map((s) => s['clientMessageId']), [key, key]);
      expect(message.id, 'msg-$key');
      expect(ctx.queue.isEmpty, isTrue);
    });
  });

  group('recovery + isolation', () {
    test('recover adopts only this room; pool releases per-user schedulers', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      // Pre-existing task from another room lives in the shared scheduler.
      final other = await makeTempFile(dir, 'other.jpg', patternBytes(100, 9));
      final shared = UploadScheduler(
          api: api, store: store, getToken: () async => 'tok', logger: silentLogger());
      addTearDown(shared.dispose);
      await shared.enqueue(
          userId: 'u', localPath: other.path, fileName: 'other.jpg',
          mimeType: 'image/jpeg', purpose: 'chat',
          scope: {'roomId': 'room-other', 'sortIndex': 0, 'kind': 'image'});
      final ctx = makeQueue(api, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      await ctx.queue.recover();
      expect(ctx.queue.isEmpty, isTrue);
    });
  });
}
