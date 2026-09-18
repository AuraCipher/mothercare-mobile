import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/upload_task.dart';

void main() {
  group('client state machine', () {
    test('terminal states are completed/cancelled/failed/expired', () {
      expect(isUploadTerminal(UploadTaskState.completed), isTrue);
      expect(isUploadTerminal(UploadTaskState.cancelled), isTrue);
      expect(isUploadTerminal(UploadTaskState.failed), isTrue);
      expect(isUploadTerminal(UploadTaskState.expired), isTrue);
      for (final s in [
        UploadTaskState.queued,
        UploadTaskState.creatingSession,
        UploadTaskState.ready,
        UploadTaskState.uploading,
        UploadTaskState.paused,
        UploadTaskState.retryWait,
        UploadTaskState.completing,
        UploadTaskState.cancelling,
      ]) {
        expect(isUploadTerminal(s), isFalse, reason: '$s');
      }
    });

    test('happy-path transitions are allowed', () {
      expect(() => assertUploadTransition(UploadTaskState.queued, UploadTaskState.creatingSession),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.creatingSession, UploadTaskState.ready),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.ready, UploadTaskState.uploading),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.uploading, UploadTaskState.completing),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.completing, UploadTaskState.completed),
          returnsNormally);
    });

    test('terminal states have no exits (failed allows only explicit user retry)', () {
      for (final s in [UploadTaskState.completed, UploadTaskState.cancelled, UploadTaskState.expired]) {
        for (final t in UploadTaskState.values) {
          expect(() => assertUploadTransition(s, t), throwsStateError, reason: '$s -> $t');
        }
      }
      // failed is driver-terminal but user-retryable with the same key.
      for (final t in UploadTaskState.values) {
        if (t == UploadTaskState.queued) continue;
        expect(() => assertUploadTransition(UploadTaskState.failed, t), throwsStateError,
            reason: 'failed -> $t');
      }
    });

    test('cancelled/completed never resume, even via queued', () {
      expect(() => assertUploadTransition(UploadTaskState.cancelled, UploadTaskState.uploading),
          throwsStateError);
      expect(() => assertUploadTransition(UploadTaskState.completed, UploadTaskState.uploading),
          throwsStateError);
      expect(() => assertUploadTransition(UploadTaskState.cancelled, UploadTaskState.queued),
          throwsStateError);
      expect(() => assertUploadTransition(UploadTaskState.expired, UploadTaskState.queued),
          throwsStateError);
    });

    test('failed allows explicit user retry via queued', () {
      expect(() => assertUploadTransition(UploadTaskState.failed, UploadTaskState.queued),
          returnsNormally);
    });

    test('pause/resume edges exist for system gating', () {
      expect(() => assertUploadTransition(UploadTaskState.uploading, UploadTaskState.paused),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.paused, UploadTaskState.queued),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.retryWait, UploadTaskState.paused),
          returnsNormally);
    });

    test('driver edges: reconcile and backoff from any active state', () {
      for (final from in [
        UploadTaskState.queued,
        UploadTaskState.creatingSession,
        UploadTaskState.ready,
        UploadTaskState.uploading,
        UploadTaskState.paused,
        UploadTaskState.completing,
      ]) {
        expect(() => assertUploadTransition(from, UploadTaskState.retryWait), returnsNormally,
            reason: '$from -> retryWait');
        expect(() => assertUploadTransition(from, UploadTaskState.failed), returnsNormally,
            reason: '$from -> failed');
      }
      expect(() => assertUploadTransition(UploadTaskState.retryWait, UploadTaskState.uploading),
          returnsNormally);
      expect(() => assertUploadTransition(UploadTaskState.queued, UploadTaskState.uploading),
          returnsNormally);
    });
  });

  group('UploadTask model', () {
    test('progress reflects server-acknowledged bytes only', () {
      final task = UploadTask(
        taskId: 't', userId: 'u', idempotencyKey: 'k', localPath: '/a',
        fileName: 'a', mimeType: 'm', purpose: 'document',
        expectedSize: 100, serverBytes: 25,
      );
      expect(task.progress, 0.25);
    });

    test('copyWith enforces transitions', () {
      final task = UploadTask(
        taskId: 't', userId: 'u', idempotencyKey: 'k', localPath: '/a',
        fileName: 'a', mimeType: 'm', purpose: 'document', expectedSize: 100,
        state: UploadTaskState.completed,
      );
      expect(() => task.copyWith(state: UploadTaskState.uploading), throwsStateError);
    });

    test('JSON round-trip preserves all recovery fields', () {
      final task = UploadTask(
        taskId: 't', userId: 'u', idempotencyKey: 'k', sessionId: 's',
        localPath: '/a/b.mp4', fileName: 'b.mp4', mimeType: 'video/mp4',
        purpose: 'video', expectedSize: 12, serverBytes: 5,
        state: UploadTaskState.paused, retryCount: 2,
        errorKind: UploadErrorKind.timeout, errorMessage: 't/o',
        fileRecordId: 'f', fileUrl: '/u/f', cancelRequested: true,
        scopeJson: '{"roomId":"r"}',
      );
      final back = UploadTask.fromJson(task.toJson());
      expect(back.toJson(), task.toJson());
      expect(back.scope, {'roomId': 'r'});
      expect(back.isVideo, isTrue);
    });

    test('idempotency keys are 128-bit hex and unique', () {
      final keys = List.generate(100, (_) => newIdempotencyKey()).toSet();
      expect(keys, hasLength(100));
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });
}
