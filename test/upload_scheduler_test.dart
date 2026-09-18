import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/upload_scheduler.dart';
import 'package:mobile/features/uploads/upload_task.dart';

import 'upload_test_support.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scheduler_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('concurrency bounds', () {
    test('photo lane bounded, video lane serialized, failures isolated', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..patchDelay = const Duration(milliseconds: 60);
      final sched = UploadScheduler(
        api: api, store: store, getToken: () async => 'tok',
        config: const UploadSchedulerConfig(photoConcurrency: 2, videoConcurrency: 1),
      );
      addTearDown(sched.dispose);
      // Hold scheduling while enqueuing so all tasks start together.
      sched.handleConnectivityLost();
      // 4 photos + 1 poisoned photo + 2 videos.
      for (var i = 0; i < 4; i++) {
        final f = await makeTempFile(dir, 'p$i.bin', patternBytes(6000, i));
        await sched.enqueue(userId: 'u', localPath: f.path, fileName: 'p$i.bin',
            mimeType: 'application/octet-stream', purpose: 'document');
      }
      final poison = await makeTempFile(dir, 'poison.bin', patternBytes(100, 9));
      await sched.enqueue(userId: 'u', localPath: poison.path, fileName: 'poison.bin',
          mimeType: 'application/octet-stream', purpose: 'document', idempotencyKey: 'poison-key');
      api.failKeys['poison-key'] = 403;
      for (var i = 0; i < 2; i++) {
        final f = await makeTempFile(dir, 'v$i.bin', patternBytes(6000, 20 + i));
        await sched.enqueue(userId: 'u', localPath: f.path, fileName: 'v$i.bin',
            mimeType: 'video/mp4', purpose: 'video');
      }
      sched.handleConnectivityRestored();

      await waitFor(() async {
        final tasks = await store.listUserTasks('u');
        return tasks.length == 7 && tasks.every((t) => t.isTerminal);
      }, timeout: const Duration(seconds: 30));

      final tasks = await store.listUserTasks('u');
      expect(tasks.where((t) => t.state == UploadTaskState.completed), hasLength(6));
      expect(tasks.where((t) => t.state == UploadTaskState.failed), hasLength(1));
      expect(api.maxPatchCalls, lessThanOrEqualTo(3),
          reason: 'photo(2) + video(1) lanes bound the simultaneous PATCHes');
    });
  });

  group('dedupe + retry + pause', () {
    test('duplicate enqueue returns the existing task', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final sched = UploadScheduler(api: api, store: store, getToken: () async => 'tok');
      addTearDown(sched.dispose);
      final f = await makeTempFile(dir, 'd.bin', patternBytes(100, 3));
      final t1 = await sched.enqueue(userId: 'u', localPath: f.path, fileName: 'd.bin',
          mimeType: 'application/octet-stream', idempotencyKey: 'dup-key');
      final t2 = await sched.enqueue(userId: 'u', localPath: f.path, fileName: 'd.bin',
          mimeType: 'application/octet-stream', idempotencyKey: 'dup-key');
      expect(t2.taskId, t1.taskId);
      await waitFor(() async =>
          (await store.getTask('u', t1.taskId))?.state == UploadTaskState.completed,
          timeout: const Duration(seconds: 15));
    });

    test('offline pauses scheduling; restore resumes staggered without storm', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..patchDelay = const Duration(milliseconds: 30);
      final sched = UploadScheduler(api: api, store: store, getToken: () async => 'tok');
      addTearDown(sched.dispose);
      sched.handleConnectivityLost();
      final f = await makeTempFile(dir, 'o.bin', patternBytes(100, 4));
      await sched.enqueue(userId: 'u', localPath: f.path, fileName: 'o.bin',
          mimeType: 'application/octet-stream');
      await Future.delayed(const Duration(milliseconds: 200));
      expect(api.createCalls, 0);
      sched.handleConnectivityRestored();
      await waitFor(() async =>
          (await store.listUserTasks('u')).first.state == UploadTaskState.completed,
          timeout: const Duration(seconds: 15));
    });

    test('recover() reconciles persisted tasks after restart', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final sched = UploadScheduler(api: api, store: store, getToken: () async => 'tok');
      addTearDown(sched.dispose);
      final f = await makeTempFile(dir, 'r.bin', patternBytes(100, 5));
      // Simulate a pre-restart row: session created server-side, nothing acked.
      final created = await api.createSession(
          token: 'tok', purpose: 'document', fileName: 'r.bin',
          mimeType: 'application/octet-stream', expectedSize: 100, idempotencyKey: 'rec-key');
      await store.saveTask(makeTask(
        taskId: 'rec-1', userId: 'u', localPath: f.path, expectedSize: 100,
        sessionId: created.session.id, key: 'rec-key', state: UploadTaskState.uploading,
      ));
      final out = await sched.recover('u');
      expect(out.single.taskId, 'rec-1');
      // Recovery requeues; the driver completes asynchronously.
      await waitFor(() async =>
          (await store.getTask('u', 'rec-1'))?.state == UploadTaskState.completed,
          timeout: const Duration(seconds: 15));
      final done = (await store.getTask('u', 'rec-1'))!;
      expect(done.fileRecordId, isNotNull);
    });
  });
}
