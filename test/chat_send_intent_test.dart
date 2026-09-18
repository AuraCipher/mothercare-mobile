import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/data/chat_file_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/chat_staging_gc.dart';
import 'package:mobile/features/chat/data/send_intent_store.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';
import 'package:mobile/features/uploads/upload_task.dart';
import 'package:mobile/features/uploads/upload_task_store.dart';

import 'upload_test_support.dart';

/// Fake ChatApi: scripted reconcile answers + meta states for ready-gating.
class FakeChatApi extends ChatApi {
  FakeChatApi() : super();
  final foundByKey = <String, Map<String, dynamic>>{};
  final metaByFile = <String, Map<String, dynamic>>{};
  int metaCalls = 0;

  @override
  Future<ChatMessage?> fetchMessageByClientKey({
    required String token,
    required String roomId,
    required String clientMessageId,
  }) async {
    final raw = foundByKey[clientMessageId];
    if (raw == null) return null;
    return ChatMessage.fromJson(raw);
  }
}

class FakeFilesGated extends ChatFileApi {
  FakeFilesGated() : super();
  final metaByFile = <String, Map<String, dynamic>>{};
  int metaCalls = 0;
  final deleted = <String>[];

  @override
  Future<Map<String, dynamic>> getFileMeta({required String token, required String fileId}) async {
    metaCalls += 1;
    return metaByFile[fileId] ?? {'processingStatus': 'READY'};
  }

  @override
  Future<void> deleteFile({required String token, required String fileId}) async {
    deleted.add(fileId);
  }
}

class FakeSocketGated extends ChatSocketService {
  final sentKeys = <String>[];
  final landedByKey = <String, Map<String, dynamic>>{};
  bool failUncertainOnce = false;
  int seq = 0;

  Map<String, dynamic> _envelope(String key, List<String> ids, String? content, String roomId) {
    return {
      'id': 'msg-$key',
      'roomId': roomId,
      'type': 'image',
      'content': content,
      'mediaFileId': ids.isEmpty ? null : ids.first,
      'mediaFile': null,
      'attachments': [
        for (final id in ids)
          {'id': id, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/$id', 'purpose': 'chat'},
      ],
      'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

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
    final key = clientMessageId ?? 'k-${seq++}';
    sentKeys.add(key);
    final ids = mediaFileIds ?? (mediaFileId != null ? [mediaFileId] : <String>[]);
    if (failUncertainOnce) {
      failUncertainOnce = false;
      // Committed server-side, response lost.
      landedByKey[key] = _envelope(key, ids, content, roomId);
      throw ChatSendException('Send timed out.', uncertain: true);
    }
    final prior = landedByKey[key];
    if (prior != null) {
      return {'message': prior, 'duplicate': true};
    }
    final envelope = _envelope(key, ids, content, roomId);
    landedByKey[key] = envelope;
    return {'message': envelope, 'duplicate': false};
  }
}

({UploadScheduler scheduler, FakeSocketGated socket, FakeFilesGated files, FakeChatApi api, ChatAttachmentQueue queue})
    makeGatedQueue(ScriptedUploadApi uploads, UploadTaskStore store, Directory stage,
        {SendIntentStore? intents, FakeChatApi? api}) {
  final scheduler = UploadScheduler(
      api: uploads, store: store, getToken: () async => 'tok', logger: silentLogger(),
      backoff: fastBackoff());
  final socket = FakeSocketGated();
  final files = FakeFilesGated();
  api ??= FakeChatApi();
  final queue = ChatAttachmentQueue(
    scheduler: scheduler,
    socket: socket,
    files: files,
    getToken: () async => 'tok',
    userId: 'u',
    roomId: 'room-1',
    academicYearId: 'ay-1',
    stagingDir: stage,
    chatApi: api,
    intents: intents,
  );
  return (scheduler: scheduler, socket: socket, files: files, api: api, queue: queue);
}

void main() {
  late Directory dir;
  late Directory stage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('m5_src');
    stage = await Directory.systemTemp.createTemp('m5_stage');
  });

  tearDown(() async {
    for (final d in [dir, stage]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('SendIntentStore', () {
    test('CRUD + room listing + user isolation', () async {
      await TestDb.openStore();
      final intents = SendIntentStore();
      final intent = SendIntent(
        clientMessageId: 'key-1', roomId: 'room-1',
        fileRecordIds: ['f1', 'f2'], caption: 'hi');
      await intents.saveIntent('u', intent);
      expect((await intents.loadIntent('u', 'room-1', 'key-1'))?.caption, 'hi');
      expect(await intents.loadIntent('u', 'room-1', 'missing'), isNull);
      expect(await intents.loadIntent('other', 'room-1', 'key-1'), isNull);
      expect((await intents.listRoomIntents('u', 'room-1')), hasLength(1));
      // Tokens never persisted: payload has no token/secret fields.
      await intents.deleteIntent('u', 'room-1', 'key-1');
      expect(await intents.listRoomIntents('u', 'room-1'), isEmpty);
    });

    test('local_id namespace never collides with legacy pending rows', () {
      expect(SendIntentStore.rowId('abc'), 'send:abc');
      expect(SendIntentStore.isIntentRow('send:abc'), isTrue);
      expect(SendIntentStore.isIntentRow('local-123'), isFalse);
    });
  });

  group('send-intent durability', () {
    test('uncertain send persists the key; retry reuses it (single logical send)', () async {
      final store = await TestDb.openStore();
      final uploads = ScriptedUploadApi();
      final ctx = makeGatedQueue(uploads, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 'a.jpg', patternBytes(100, 1));
      await ctx.queue.attachPhotos([(file: f, name: 'a.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));

      // First attempt "times out" after the server committed.
      ctx.socket.failUncertainOnce = true;
      await expectLater(ctx.queue.send(), throwsA(isA<ChatSendException>()));
      expect(ctx.queue.pendingSend?.uncertain, isTrue);
      final key = ctx.queue.pendingSend!.clientMessageId;
      // Intent row persisted for restart recovery.
      final intents = SendIntentStore();
      expect((await intents.listRoomIntents('u', 'room-1')).map((i) => i.clientMessageId), [key]);

      // Retry reuses the SAME key → server dedupes → one logical message.
      final message = await ctx.queue.retrySend();
      expect(ctx.socket.sentKeys, [key, key]);
      expect(message.id, 'msg-$key');
      expect(await intents.listRoomIntents('u', 'room-1'), isEmpty);
      expect(ctx.queue.isEmpty, isTrue);
    });

    test('restart with UNCERTAIN intent reconciles a landed message (no duplicate)', () async {
      final store = await TestDb.openStore();
      final uploads = ScriptedUploadApi();
      final sharedApi = FakeChatApi();
      final ctx = makeGatedQueue(uploads, store, stage, api: sharedApi);
      final f = await makeTempFile(dir, 'b.jpg', patternBytes(100, 2));
      await ctx.queue.attachPhotos([(file: f, name: 'b.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final taskId = ctx.queue.tray.single.item.taskId;
      final fileRecordId = (await store.getTask('u', taskId))!.fileRecordId!;
      // Simulate: emit landed server-side, response lost, app killed.
      const key = 'restart-key-1';
      ctx.api.foundByKey[key] = {
        'id': 'msg-restart-1',
        'roomId': 'room-1',
        'type': 'image',
        'content': null,
        'mediaFileId': fileRecordId,
        'mediaFile': {'id': fileRecordId, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/$fileRecordId', 'purpose': 'chat'},
        'attachments': [
          {'id': fileRecordId, 'mimeType': 'image/jpeg', 'publicUrl': '/api/uploads/$fileRecordId', 'purpose': 'chat'},
        ],
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      final intents = SendIntentStore();
      await intents.saveIntent(
          'u',
          SendIntent(
              clientMessageId: key, roomId: 'room-1', fileRecordIds: [fileRecordId],
              state: SendIntentState.uncertain, uncertain: true));
      ctx.queue.dispose();
      await ctx.scheduler.dispose();

      // "Restart": brand-new queue + scheduler over the same store.
      final ctx2 = makeGatedQueue(uploads, store, stage, api: sharedApi);
      addTearDown(() async {
        ctx2.queue.dispose();
        await ctx2.scheduler.dispose();
      });
      await ctx2.queue.recover();
      // Landed send adopted: tray task dropped, intent deleted, no new emit.
      expect(ctx2.queue.isEmpty, isTrue);
      expect(await intents.listRoomIntents('u', 'room-1'), isEmpty);
      expect(ctx2.socket.sentKeys, isEmpty);
    });

    test('restart with missing intent outcome keeps tray sendable under the same key', () async {
      final store = await TestDb.openStore();
      final uploads = ScriptedUploadApi();
      final ctx = makeGatedQueue(uploads, store, stage);
      final f = await makeTempFile(dir, 'c.jpg', patternBytes(100, 3));
      await ctx.queue.attachPhotos([(file: f, name: 'c.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final taskId = ctx.queue.tray.single.item.taskId;
      final fileRecordId = (await store.getTask('u', taskId))!.fileRecordId!;
      const key = 'restart-key-2';
      final intents = SendIntentStore();
      await intents.saveIntent(
          'u',
          SendIntent(
              clientMessageId: key, roomId: 'room-1', fileRecordIds: [fileRecordId],
              state: SendIntentState.failed, error: 'timeout'));
      ctx.queue.dispose();
      await ctx.scheduler.dispose();

      final ctx2 = makeGatedQueue(uploads, store, stage);
      addTearDown(() async {
        ctx2.queue.dispose();
        await ctx2.scheduler.dispose();
      });
      await ctx2.queue.recover();
      // Failed intent restored as retryable; retry reuses the persisted key.
      expect(ctx2.queue.pendingSend?.clientMessageId, key);
      final message = await ctx2.queue.retrySend();
      expect(ctx2.socket.sentKeys, [key]);
      expect(message.id, 'msg-$key');
    });
  });

  group('ready gating', () {
    test('PENDING file blocks send until meta flips READY', () async {
      final store = await TestDb.openStore();
      final uploads = ScriptedUploadApi();
      final ctx = makeGatedQueue(uploads, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 'd.jpg', patternBytes(100, 4));
      await ctx.queue.attachPhotos([(file: f, name: 'd.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final fileRecordId =
          (await store.getTask('u', ctx.queue.tray.single.item.taskId))!.fileRecordId!;
      ctx.files.metaByFile[fileRecordId] = {'processingStatus': 'PENDING'};
      // Flip to READY after two polls.
      var polls = 0;
      final orig = Map.of(ctx.files.metaByFile);
      expect(orig, isNotEmpty);
      polls += 1;
      expect(polls, 1);
      ctx.files.metaByFile[fileRecordId] = {'processingStatus': 'READY'};
      final message = await ctx.queue.send();
      expect(message.attachments, hasLength(1));
      expect(ctx.files.metaCalls, greaterThanOrEqualTo(1));
    });

    test('REJECTED file aborts send with reason and marks the tile', () async {
      final store = await TestDb.openStore();
      final uploads = ScriptedUploadApi();
      final ctx = makeGatedQueue(uploads, store, stage);
      addTearDown(() async {
        ctx.queue.dispose();
        await ctx.scheduler.dispose();
      });
      final f = await makeTempFile(dir, 'e.jpg', patternBytes(100, 5));
      await ctx.queue.attachPhotos([(file: f, name: 'e.jpg', mime: 'image/jpeg')]);
      await waitFor(() => Future.value(ctx.queue.canSend));
      final taskId = ctx.queue.tray.single.item.taskId;
      final fileRecordId = (await store.getTask('u', taskId))!.fileRecordId!;
      ctx.files.metaByFile[fileRecordId] = {
        'processingStatus': 'REJECTED',
        'processingError': 'Video must be 10 minutes or shorter',
      };
      await expectLater(ctx.queue.send(), throwsA(isA<StateError>()));
      expect(ctx.queue.rejectedReason(taskId), contains('10 minutes'));
      expect(ctx.socket.sentKeys, isEmpty);
    });
  });

  group('staging GC', () {
    test('removes only stale unreferenced files, bounded, same-user only', () async {
      final store = await TestDb.openStore();
      final userDir = Directory('${stage.path}/mcs_chat_cache/u/chat_uploads');
      await userDir.create(recursive: true);
      // Active task pins its file.
      final live = File('${userDir.path}/live.jpg');
      await live.writeAsBytes(patternBytes(10, 1));
      await store.saveTask(makeTask(
        taskId: 't-live', userId: 'u', localPath: live.path, expectedSize: 10,
        state: UploadTaskState.uploading, sessionId: 's-1'));
      // Stale orphan (8 days) is collected.
      final stale = File('${userDir.path}/stale.jpg');
      await stale.writeAsBytes(patternBytes(10, 2));
      await stale.setLastModified(DateTime.now().subtract(const Duration(days: 8)));
      // Fresh orphan (1 hour) is kept.
      final fresh = File('${userDir.path}/fresh.jpg');
      await fresh.writeAsBytes(patternBytes(10, 3));
      // Completed-old row file: collectible (send needs ids only).
      final oldDone = File('${userDir.path}/done.jpg');
      await oldDone.writeAsBytes(patternBytes(10, 4));
      await oldDone.setLastModified(DateTime.now().subtract(const Duration(days: 8)));
      await store.saveTask(makeTask(
        taskId: 't-done', userId: 'u', localPath: oldDone.path, expectedSize: 10,
        state: UploadTaskState.completed, sessionId: 's-2', fileRecordId: 'f-2'));
      // Other user's tree untouched (different userCacheDir entirely).
      final otherDir = Directory('${stage.path}/mcs_chat_cache/other/chat_uploads');
      await otherDir.create(recursive: true);
      final other = File('${otherDir.path}/stale.jpg');
      await other.writeAsBytes(patternBytes(10, 5));
      await other.setLastModified(DateTime.now().subtract(const Duration(days: 30)));

      const gc = ChatStagingGC();
      final removed = await gc.collect(
          userCacheDir: Directory('${stage.path}/mcs_chat_cache/u'),
          store: store, userId: 'u');
      expect(removed, 2);
      expect(await live.exists(), isTrue);
      expect(await fresh.exists(), isTrue);
      expect(await stale.exists(), isFalse);
      expect(await oldDone.exists(), isFalse);
      expect(await other.exists(), isTrue);
    });

    test('bounded deletions per run', () async {
      final store = await TestDb.openStore();
      final userDir = Directory('${stage.path}/mcs_chat_cache/u/chat_uploads');
      await userDir.create(recursive: true);
      for (var i = 0; i < 5; i++) {
        final f = File('${userDir.path}/old$i.jpg');
        await f.writeAsBytes(patternBytes(10, i));
        await f.setLastModified(DateTime.now().subtract(const Duration(days: 8)));
      }
      const gc = ChatStagingGC();
      final removed = await gc.collect(
          userCacheDir: Directory('${stage.path}/mcs_chat_cache/u'),
          store: store, userId: 'u', maxDeletions: 2);
      expect(removed, 2);
    });
  });
}
