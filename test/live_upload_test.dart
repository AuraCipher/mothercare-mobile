import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/resumable_upload_engine.dart';
import 'package:mobile/features/uploads/upload_session_api.dart';
import 'package:mobile/features/uploads/upload_task.dart';

import 'upload_test_support.dart';

/// Opt-in live test against a real local backend (M1/M2 endpoints).
///
/// Runs ONLY when all three are present:
///   M3_LIVE_BACKEND=1 M3_API_URL=http://127.0.0.1:5000 M3_TOKEN=`<jwt>`
///
/// Exercises create → GET → PATCH chunks → complete → cancel for real,
/// including one file large enough to cross multiple 5 MiB chunks.
/// Skipped in normal CI (no live R2 or backend required).
void main() {
  final enabled = Platform.environment['M3_LIVE_BACKEND'] == '1';
  final baseUrl = Platform.environment['M3_API_URL'] ?? 'http://127.0.0.1:5000';
  final token = Platform.environment['M3_TOKEN'] ?? '';

  test('live resumable upload against local backend', () async {
    if (!enabled || token.isEmpty) {
      markTestSkipped('Set M3_LIVE_BACKEND=1 M3_API_URL=... M3_TOKEN=... to run.');
      return;
    }
    final store = await TestDb.openStore();
    final api = UploadSessionApi(baseUrl: baseUrl);
    final engine = ResumableUploadEngine(
      api: api,
      store: store,
      getToken: () async => token,
    );
    addTearDown(engine.dispose);

    final dir = await Directory.systemTemp.createTemp('m3_live');
    addTearDown(() => dir.delete(recursive: true));
    // ~11 MiB: 5 + 5 + 1 MiB across three PATCHes. Named .pdf so the
    // backend's extension-fallback allowlist applies (bytes are synthetic;
    // production files carry real magic bytes).
    final file = await makeTempFile(dir, 'live.pdf', patternBytes(11 * 1024 * 1024, 7));
    final size = await file.length();
    var task = UploadTask(
      taskId: 'live-1',
      userId: 'live-user',
      idempotencyKey: 'live-key-${DateTime.now().millisecondsSinceEpoch}',
      localPath: file.path,
      fileName: 'live.pdf',
      mimeType: 'application/pdf',
      purpose: 'document',
      expectedSize: size,
    );
    await store.saveTask(task);

    task = await engine.runTask(task).timeout(const Duration(minutes: 5));
    expect(task.state, UploadTaskState.completed);
    expect(task.fileRecordId, isNotNull);
    expect(task.serverBytes, size);

    // Cancel path for real.
    final cancelFile = await makeTempFile(dir, 'cancel.bin', patternBytes(100, 1));
    var task2 = UploadTask(
      taskId: 'live-2',
      userId: 'live-user',
      idempotencyKey: 'live-key-cancel-${DateTime.now().millisecondsSinceEpoch}',
      localPath: cancelFile.path,
      fileName: 'cancel.bin',
      mimeType: 'application/octet-stream',
      purpose: 'document',
      expectedSize: 100,
      cancelRequested: true,
    );
    await store.saveTask(task2);
    task2 = await engine.runTask(task2).timeout(const Duration(minutes: 1));
    expect(task2.state, UploadTaskState.cancelled);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
