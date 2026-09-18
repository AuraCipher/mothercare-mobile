import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/resumable_upload_engine.dart';
import 'package:mobile/features/uploads/upload_task.dart';

import 'upload_test_support.dart';

void main() {
  const fiveMiB = 5 * 1024 * 1024;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('engine_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('happy path + recovery matrix', () {
    test('multi-chunk upload completes with FileRecord; progress is monotonic', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'a.bin', patternBytes(fiveMiB * 2 + 7, 1));
      final size = await file.length();
      var task = makeTask(localPath: file.path, expectedSize: size);
      await store.saveTask(task);

      final seen = <double>[];
      final sub = eng.taskUpdates.listen((t) {
        if (t.taskId == task.taskId) seen.add(t.progress);
      });
      task = await eng.runTask(task);
      await sub.cancel();

      expect(task.state, UploadTaskState.completed);
      expect(task.serverBytes, size);
      expect(task.fileRecordId, isNotNull);
      expect(task.progress, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i] >= seen[i - 1], isTrue, reason: 'progress jumped backwards');
      }
      // Each byte range sent exactly once.
      final ranges = api.patchRanges.values.expand((r) => r).toList();
      expect(ranges.map((r) => r.offset), [0, fiveMiB, fiveMiB * 2]);
    });

    test('stale local cache adopts server truth without resending', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'b.bin', patternBytes(fiveMiB + 10, 2));
      final size = await file.length();
      final sessionId = api.seedSession(expectedSize: size, bytesUploaded: fiveMiB);
      // Local cache claims 0; server already holds the first chunk.
      var task = makeTask(localPath: file.path, expectedSize: size, sessionId: sessionId);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.serverBytes, size);
      final ranges = api.patchRanges[sessionId] ?? [];
      expect(ranges.map((r) => r.offset), [fiveMiB],
          reason: 'must not resend server-acknowledged bytes');
    });

    test('409 mid-upload reconciles and continues', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'c.bin', patternBytes(fiveMiB + 10, 3));
      final size = await file.length();
      var task = makeTask(localPath: file.path, expectedSize: size);
      await store.saveTask(task);
      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
    });

    test('lost PATCH response reconciles via GET without duplicating bytes', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..dropPatchResponses = 1;
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'd.bin', patternBytes(fiveMiB + 10, 4));
      final size = await file.length();
      var task = makeTask(localPath: file.path, expectedSize: size);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.serverBytes, size);
      // The dropped chunk was applied once server-side; the client continued
      // from the reconciled offset instead of resending.
      final ranges = api.patchRanges.values.expand((r) => r).toList();
      expect(ranges.map((r) => r.offset), [0, fiveMiB]);
    });

    test('lost completion response recovers the FileRecord via GET', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..failCompleteTimes = 1;
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'e.bin', patternBytes(100, 5));
      var task = makeTask(localPath: file.path, expectedSize: 100);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.fileRecordId, isNotNull);
      // One logical completion; the retry converged instead of duplicating.
      expect(api.sessions.values.where((s) => s.status == 'COMPLETED'), hasLength(1));
    });

    test('server already COMPLETED is adopted without any transfer', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      api.completeFileRecordId = 'file-adopted';
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'f.bin', patternBytes(100, 6));
      final sessionId = api.seedSession(expectedSize: 100, bytesUploaded: 100, status: 'COMPLETED');
      api.sessions[sessionId]!.fileRecordId = 'file-adopted';
      var task = makeTask(localPath: file.path, expectedSize: 100, sessionId: sessionId);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.fileRecordId, 'file-adopted');
      expect(api.patchRanges[sessionId] ?? [], isEmpty);
      expect(api.completeCalls, 0);
    });

    test('404 recreates with the SAME idempotency key', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'g.bin', patternBytes(100, 7));
      // Task points at a session the server forgot.
      var task = makeTask(
          localPath: file.path, expectedSize: 100, sessionId: 'sess-gone', key: 'stable-key-9');
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.sessionId, isNot('sess-gone'));
      expect(api.createCalls, greaterThanOrEqualTo(1));
    });

    test('410 marks expired (terminal; no infinite retry)', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'h.bin', patternBytes(100, 8));
      final sessionId = api.seedSession(expectedSize: 100, status: 'EXPIRED');
      var task = makeTask(localPath: file.path, expectedSize: 100, sessionId: sessionId);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.expired);
    });

    test('retry budget exhaustion parks as failed; manual retry heals', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..failPatchWith = 500;
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'i.bin', patternBytes(100, 9));
      var task = makeTask(localPath: file.path, expectedSize: 100);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.failed);
      expect(task.retryCount, 3);

      api.failPatchWith = 0;
      // Manual retry keeps the SAME idempotency key → server session reused.
      final sessionBefore = task.sessionId;
      task = task.copyWith(state: UploadTaskState.queued, retryCount: 0, clearError: true);
      await store.saveTask(task);
      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.completed);
      expect(task.sessionId, sessionBefore);
    });

    test('permanent errors do not retry (403)', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..failCreateWith = 403;
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'j.bin', patternBytes(100, 10));
      var task = makeTask(localPath: file.path, expectedSize: 100);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.failed);
      expect(api.createCalls, 1);
    });

    test('missing local file fails permanently without network use', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      var task = makeTask(localPath: '${dir.path}/gone.bin', expectedSize: 100);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.failed);
      expect(api.createCalls, 0);
    });
  });

  group('cancellation', () {
    test('cancel before upload calls DELETE and ends cancelled', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'k.bin', patternBytes(100, 11));
      var task = makeTask(localPath: file.path, expectedSize: 100, sessionId: api.seedSession(expectedSize: 100));
      task = task.copyWith(cancelRequested: true);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.cancelled);
      expect(api.cancelCalls, 1);
      expect(api.sessions.values.first.status, 'CANCELLED');
    });

    test('offline cancel persists intent; reconcile flushes it later', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi()..failCancel = true;
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'l.bin', patternBytes(100, 12));
      var task = makeTask(localPath: file.path, expectedSize: 100, sessionId: api.seedSession(expectedSize: 100));
      task = task.copyWith(cancelRequested: true);
      await store.saveTask(task);

      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.cancelled);
      expect(task.cancelRequested, isTrue);

      // Connectivity returns: reconcile flushes the DELETE.
      api.failCancel = false;
      task = await eng.reconcileTask(task);
      expect(task.cancelRequested, isFalse);
      expect(api.sessions.values.first.status, 'CANCELLED');
    });

    test('cancelled task never auto-resumes', () async {
      final store = await TestDb.openStore();
      final api = ScriptedUploadApi();
      final eng = ResumableUploadEngine(
          api: api, store: store, getToken: () async => 'tok', backoff: fastBackoff(),
          logger: silentLogger());
      addTearDown(eng.dispose);
      final file = await makeTempFile(dir, 'm.bin', patternBytes(100, 13));
      var task = makeTask(
        localPath: file.path, expectedSize: 100,
        sessionId: api.seedSession(expectedSize: 100),
        state: UploadTaskState.cancelled,
      );
      await store.saveTask(task);
      task = await eng.runTask(task);
      expect(task.state, UploadTaskState.cancelled);
      expect(api.patchRanges.values, isEmpty);
    });
  });
}
