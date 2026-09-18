import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'chunk_reader.dart';
import 'upload_backoff.dart';
import 'upload_diagnostics.dart';
import 'upload_errors.dart';
import 'upload_session_api.dart';
import 'upload_task.dart';
import 'upload_task_store.dart';

/// Server protocol chunk size (bytes). MUST match the backend
/// TRANSFER_PART_SIZE: every non-final chunk is exactly this; the final
/// chunk is the remainder. Single source of truth client-side.
const int protocolChunkSize = 5 * 1024 * 1024;

typedef UploadTokenProvider = Future<String?> Function();

/// Cooperative cancellation for one task run. package:http cannot abort an
/// in-flight socket, so cancellation means: stop scheduling, ignore the
/// in-flight outcome, reconcile afterwards via GET/DELETE.
class UploadCancellation {
  bool _requested = false;
  bool get isRequested => _requested;
  void request() => _requested = true;
}

/// Drives ONE upload task through its lifecycle. The scheduler owns
/// concurrency; this class owns correctness for a single file.
///
/// Recovery contract (read before modifying):
/// - SQLite offset is a cached hint; the server offset is truth.
/// - After ANY uncertain PATCH outcome (timeout, connection loss, 409,
///   app restart, retry), GET the session and continue from ITS offset.
/// - Never resend bytes the server already acknowledged.
/// - Completion is idempotent: a lost completion response is recovered by
///   GET (COMPLETED ⇒ adopt fileRecord) rather than blind re-completion.
class ResumableUploadEngine {
  ResumableUploadEngine({
    required UploadSessionApi api,
    required UploadTaskStore store,
    required UploadTokenProvider getToken,
    UploadErrorClassifier classifier = const UploadErrorClassifier(),
    UploadBackoffPolicy? backoff,
    ChunkReader chunkReader = const ChunkReader(),
    UploadLogger? logger,
    Future<bool> Function(UploadTask task)? canProceed,
    Random? random,
  })  : _api = api,
        _store = store,
        _getToken = getToken,
        _classifier = classifier,
        _backoff = backoff ?? UploadBackoffPolicy(random: random),
        _reader = chunkReader,
        _logger = logger ?? UploadLogger(),
        _canProceed = canProceed ?? ((_) async => true);

  final UploadSessionApi _api;
  final UploadTaskStore _store;
  final UploadTokenProvider _getToken;
  final UploadErrorClassifier _classifier;
  final UploadBackoffPolicy _backoff;
  final ChunkReader _reader;
  final UploadLogger _logger;
  final Future<bool> Function(UploadTask task) _canProceed;

  final _updates = StreamController<UploadTask>.broadcast();

  /// Every persisted mutation, in order. Progress UIs listen here.
  Stream<UploadTask> get taskUpdates => _updates.stream;

  void dispose() => _updates.close();

  Future<UploadTask> _save(UploadTask task) async {
    await _store.saveTask(task);
    if (!_updates.isClosed) _updates.add(task);
    return task;
  }

  void _log(UploadDiagnostic d) => _logger.log(d);

  Future<String?> _tokenOrFail(UploadTask task) async {
    final token = await _getToken();
    return token;
  }

  /// One-shot reconcile: GET the session and adopt ITS truth. Also flushes a
  /// pending cancel intent (cancelled + cancelRequested + live session).
  /// Returns the persisted task (possibly terminal).
  Future<UploadTask> reconcileTask(UploadTask task) async {
    final token = await _tokenOrFail(task);
    // Terminal tasks are returned as-is, except a cancelled task may still
    // carry an unflushed server-cancel intent (offline cancel).
    final needsCancelFlush = task.state == UploadTaskState.cancelled &&
        task.cancelRequested &&
        task.sessionId != null;
    if (token == null) {
      if (task.isTerminal) return task;
      return _save(task.copyWith(
        state: UploadTaskState.failed,
        errorKind: UploadErrorKind.auth,
        errorMessage: 'Not signed in. Please sign in again.',
      ));
    }
    if (task.sessionId == null || (task.isTerminal && !needsCancelFlush)) return task;
    try {
      final remote = await _api.getSession(token: token, sessionId: task.sessionId!);
      task = _adoptRemote(task, remote);
      await _save(task);
      // Flush a cancellation that previously failed offline.
      if (task.state == UploadTaskState.cancelled &&
          task.cancelRequested &&
          task.sessionId != null) {
        try {
          await _api.cancelSession(token: token, sessionId: task.sessionId!);
          task = await _save(task.copyWith(cancelRequested: false));
        } catch (_) {
          // Still offline: intent stays persisted for the next resume.
        }
      }
      return task;
    } on UploadApiException catch (e) {
      if (e.statusCode == 404) {
        // Server forgot the session and we have no bytes proof: the task
        // keeps its local state; the next run recreates with the same key.
        return task;
      }
      rethrow;
    }
  }

  /// Adopt server truth. Server bytes ALWAYS win — even over a larger local
  /// cache (which cannot happen by construction, but defense in depth: the
  /// server is authoritative, period).
  UploadTask _adoptRemote(UploadTask task, RemoteUploadSession remote) {
    _log(UploadDiagnostic(
      event: 'reconcile',
      taskId: task.taskId,
      sessionId: remote.id,
      offset: remote.bytesUploaded,
      message: 'server=${remote.bytesUploaded} local=${task.serverBytes} status=${remote.status}',
    ));
    var next = task.copyWith(
      sessionId: remote.id,
      serverBytes: remote.bytesUploaded,
      clearError: true,
      clearNextRetry: true,
    );
    switch (remote.status) {
      case 'COMPLETED':
        if (remote.fileRecordId != null) {
          next = next.copyWith(
            state: UploadTaskState.completed,
            fileRecordId: remote.fileRecordId,
            fileUrl: remote.fileUrl,
          );
        }
        // COMPLETED without a fileRecord link: fall through to normal flow —
        // the completer will converge (idempotent completion).
        break;
      case 'CANCELLED':
        if (next.state != UploadTaskState.cancelled) {
          next = next.copyWith(state: UploadTaskState.cancelled, cancelRequested: false);
        }
        break;
      case 'EXPIRED':
        if (!next.isTerminal) {
          next = next.copyWith(
            state: UploadTaskState.expired,
            errorKind: UploadErrorKind.gone,
            errorMessage: 'Upload session expired.',
          );
        }
        break;
      case 'FAILED':
        if (!next.isTerminal) {
          next = next.copyWith(
            state: UploadTaskState.failed,
            errorKind: UploadErrorKind.validation,
            errorMessage: 'Server rejected the upload.',
          );
        }
        break;
      default:
        if (next.state == UploadTaskState.queued ||
            next.state == UploadTaskState.paused ||
            next.state == UploadTaskState.retryWait ||
            next.state == UploadTaskState.ready) {
          next = next.copyWith(state: UploadTaskState.uploading);
        }
    }
    return next;
  }

  /// Runs [task] until it reaches a terminal-or-paused state. Safe to call
  /// again after process death, connectivity loss, or user retry: every
  /// uncertain point re-reads the server first.
  Future<UploadTask> runTask(UploadTask task, {UploadCancellation? cancel}) async {
    final stop = cancel ?? UploadCancellation();
    cancel = stop;
    var completes = 0;

    // eslint-disable-next-line no-constant-condition
    while (true) {
      if (cancel.isRequested || task.cancelRequested) {
        return _doCancel(task);
      }
      if (!await _canProceed(task)) {
        return _pause(task, 'Paused.');
      }

      // 0) Local file must exist and match the enqueued size.
      final file = File(task.localPath);
      final exists = await file.exists();
      if (!exists) {
        return _fail(task, UploadErrorKind.fileGone, 'Local file is no longer available.');
      }
      int actualSize;
      try {
        actualSize = await _reader.fileLength(file);
      } catch (e) {
        return _fail(task, UploadErrorKind.fileGone, 'Local file is no longer readable.');
      }
      if (actualSize != task.expectedSize) {
        return _fail(task, UploadErrorKind.validation,
            'Local file changed (expected ${task.expectedSize}, found $actualSize).');
      }
      if (task.expectedSize <= 0) {
        return _fail(task, UploadErrorKind.validation, 'Invalid file size.');
      }

      final token = await _tokenOrFail(task);
      if (token == null) {
        return _fail(task, UploadErrorKind.auth, 'Not signed in. Please sign in again.');
      }

      // 1) Ensure a server session (stable idempotency key across retries).
      if (task.sessionId == null) {
        if (task.state != UploadTaskState.creatingSession &&
            task.state != UploadTaskState.uploading) {
          task = await _save(task.copyWith(state: UploadTaskState.creatingSession, clearError: true));
        }
        _log(UploadDiagnostic(event: 'create', taskId: task.taskId, toState: task.state));
        try {
          final created = await _api.createSession(
            token: token,
            purpose: task.purpose,
            fileName: task.fileName,
            mimeType: task.mimeType,
            expectedSize: task.expectedSize,
            idempotencyKey: task.idempotencyKey,
            entityType: _scope(task, 'entityType'),
            entityId: _scope(task, 'entityId'),
            roomId: _scope(task, 'roomId'),
            academicYearId: _scope(task, 'academicYearId'),
            metadata: _scopeMap(task, 'metadata'),
          );
          // Reuse case: the server may ALREADY hold bytes for this key —
          // adopt them instead of starting at zero.
          task = await _save(task.copyWith(
            sessionId: created.session.id,
            serverBytes: created.session.bytesUploaded,
            state: UploadTaskState.ready,
          ));
          _log(UploadDiagnostic(
            event: created.created ? 'created' : 'reused',
            taskId: task.taskId,
            sessionId: created.session.id,
            offset: created.session.bytesUploaded,
          ));
        } catch (e) {
          task = await _handleError(task, e, bodyWasSent: false, cancel: cancel, token: token);
          if (task.isTerminal || task.state == UploadTaskState.paused) return task;
          continue;
        }
      }

      // 2) Reconcile with the authoritative offset before sending anything.
      try {
        task = await _reconcileOrRecreate(task, token);
      } catch (e) {
        task = await _handleError(task, e, bodyWasSent: false, cancel: cancel, token: token);
        if (task.isTerminal || task.state == UploadTaskState.paused) return task;
        continue;
      }
      if (task.isTerminal) return task;
      if (task.state == UploadTaskState.paused) return task;

      // 3) Chunk loop.
      while (task.serverBytes < task.expectedSize) {
        if (cancel.isRequested || task.cancelRequested) break;
        if (!await _canProceed(task)) {
          return _pause(task, 'Paused.');
        }
        final offset = task.serverBytes;
        final length = min(protocolChunkSize, task.expectedSize - offset);
        late final List<int> bytes;
        try {
          bytes = await _reader.readRange(file, offset, length);
        } on FileSystemException {
          return _fail(task, UploadErrorKind.fileGone, 'Local file is no longer readable.');
        } catch (e) {
          return _fail(task, UploadErrorKind.validation, e.toString());
        }
        if (task.state != UploadTaskState.uploading) {
          task = await _save(task.copyWith(state: UploadTaskState.uploading, clearError: true));
        }
        final chunkNumber = offset ~/ protocolChunkSize + 1;
        _log(UploadDiagnostic(
          event: 'chunk', taskId: task.taskId, sessionId: task.sessionId,
          offset: offset, bytes: length, chunkNumber: chunkNumber));
        try {
          final ack = await _api.sendChunk(
            token: token,
            sessionId: task.sessionId!,
            offset: offset,
            bytes: bytes,
            onCancel: () => stop.isRequested,
          );
          // The ack IS the new truth — adopt exactly.
          task = await _save(task.copyWith(serverBytes: ack.bytesUploaded));
        } on UploadChunkCancelled {
          break; // fall through to the cancel check at the top
        } catch (e) {
          // Handled task is persisted (parked or reconciled-adopted); the
          // outer loop re-checks cancel/gating and reconciles before sending.
          task = await _handleChunkError(task, e, cancel: cancel, token: token);
          if (task.isTerminal || task.state == UploadTaskState.paused) return task;
          break;
        }
      }
      if (cancel.isRequested || task.cancelRequested) continue; // top handles cancel
      if (task.serverBytes < task.expectedSize) {
        // Parked mid-loop (paused) — the return above already handled it;
        // anything else means progress state changed: re-drive from the top.
        if (task.state == UploadTaskState.paused) return task;
        continue;
      }

      // 4) Complete (idempotent; bounded replays).
      if (task.state != UploadTaskState.completing) {
        task = await _save(task.copyWith(state: UploadTaskState.completing));
      }
      try {
        final done = await _api.completeSession(token: token, sessionId: task.sessionId!);
        task = await _save(task.copyWith(
          state: UploadTaskState.completed,
          serverBytes: done.session.bytesUploaded,
          fileRecordId: done.fileRecordId ?? done.session.fileRecordId,
          fileUrl: done.session.fileUrl,
          clearError: true,
        ));
        _log(UploadDiagnostic(
          event: 'completed', taskId: task.taskId, sessionId: task.sessionId,
          message: 'fileRecord=${task.fileRecordId}'));
        return task;
      } catch (e) {
        if (e is UploadChunkCancelled) continue;
        final c = _classifier.classify(e, bodyWasSent: true);
        if (c.action == UploadAction.reconcileNow || c.action == UploadAction.retryAfterBackoff) {
          try {
            task = await _reconcileOrRecreate(task, token);
          } catch (re) {
            task = await _handleError(task, re, bodyWasSent: false, cancel: cancel, token: token);
            if (task.isTerminal || task.state == UploadTaskState.paused) return task;
            continue;
          }
          if (task.state == UploadTaskState.completed) return task;
          if (task.isTerminal || task.state == UploadTaskState.paused) return task;
          completes += 1;
          if (completes >= 3) {
            return _fail(task, c.kind, 'Completion did not converge; please retry. (${c.message})');
          }
          if (task.serverBytes < task.expectedSize) continue; // server says incomplete → more chunks
          continue; // re-attempt completion (bounded)
        }
        if (c.action == UploadAction.markExpired) {
          return _save(task.copyWith(
              state: UploadTaskState.expired,
              errorKind: c.kind, errorMessage: c.message));
        }
        return _fail(task, c.kind, c.message);
      }
    }
  }

  final _recreates = <String, int>{};

  /// GET-adopt; on 404 recreates with the SAME key (bounded) and re-adopts.
  Future<UploadTask> _reconcileOrRecreate(UploadTask task, String token) async {
    RemoteUploadSession? remote;
    try {
      remote = await _api.getSession(token: token, sessionId: task.sessionId!);
    } on UploadApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      remote = await _recreateSession(task, token);
      if (remote == null) {
        return _fail(task, UploadErrorKind.notFound, 'Upload session not found on server.');
      }
    }
    task = _adoptRemote(task, remote);
    final saved = await _save(task);
    return saved;
  }

  /// Recreates the server session with the SAME idempotency key (bounded to
  /// 2 per task) and returns the fresh remote, or null when exhausted.
  Future<RemoteUploadSession?> _recreateSession(UploadTask task, String token) async {
    final n = (_recreates[task.taskId] ?? 0) + 1;
    _recreates[task.taskId] = n;
    if (n > 2) return null;
    _log(UploadDiagnostic(event: 'recreate', taskId: task.taskId, attempt: n));
    final created = await _api.createSession(
      token: token,
      purpose: task.purpose,
      fileName: task.fileName,
      mimeType: task.mimeType,
      expectedSize: task.expectedSize,
      idempotencyKey: task.idempotencyKey,
      entityType: _scope(task, 'entityType'),
      entityId: _scope(task, 'entityId'),
      roomId: _scope(task, 'roomId'),
      academicYearId: _scope(task, 'academicYearId'),
      metadata: _scopeMap(task, 'metadata'),
    );
    final updated = await _save(task.copyWith(
      sessionId: created.session.id,
      serverBytes: created.session.bytesUploaded,
      state: UploadTaskState.ready,
    ));
    final remote = await _api.getSession(token: token, sessionId: updated.sessionId!);
    return remote;
  }

  /// Classifies a chunk failure, persists the outcome, and returns the task.
  Future<UploadTask> _handleChunkError(
    UploadTask task, Object e, {required UploadCancellation cancel, required String token}) async {
    final c = _classifier.classify(e, bodyWasSent: true);
    _log(UploadDiagnostic(
      event: 'chunk-error', taskId: task.taskId, sessionId: task.sessionId,
      errorKind: c.kind, attempt: task.retryCount + 1, message: c.message));
    switch (c.action) {
      case UploadAction.reconcileNow:
        UploadTask reconciled;
        try {
          final remote = await _api.getSession(token: token, sessionId: task.sessionId!);
          reconciled = _adoptRemote(task, remote);
        } catch (re) {
          return _handleError(task, re, bodyWasSent: false, cancel: cancel, token: token);
        }
        final saved = await _save(reconciled);
        return saved;
      case UploadAction.retryAfterBackoff:
        final handled = await _handleError(task, e, bodyWasSent: true, cancel: cancel, token: token);
        return handled;
      case UploadAction.recreateSession:
        UploadTask recreated;
        try {
          recreated = await _reconcileOrRecreate(task, token);
        } catch (re) {
          return _handleError(task, re, bodyWasSent: false, cancel: cancel, token: token);
        }
        return recreated;
      case UploadAction.markExpired:
        return _save(task.copyWith(
            state: UploadTaskState.expired, errorKind: c.kind, errorMessage: c.message));
      case UploadAction.failPermanent:
      case UploadAction.retryNow:
        return _handleError(task, e, bodyWasSent: true, cancel: cancel, token: token);
    }
  }

  /// Shared backoff/terminal handling for non-reconciled errors. Persists and
  /// returns the task; the caller decides whether to continue the loop.
  Future<UploadTask> _handleError(
    UploadTask task, Object e, {required bool bodyWasSent,
    required UploadCancellation cancel, required String token}) async {
    final c = _classifier.classify(e, bodyWasSent: bodyWasSent);
    _log(UploadDiagnostic(
      event: 'error', taskId: task.taskId, sessionId: task.sessionId,
      errorKind: c.kind, attempt: task.retryCount + 1, message: c.message));
    switch (c.action) {
      case UploadAction.retryNow:
        return _save(task.copyWith(clearError: true));
      case UploadAction.retryAfterBackoff:
        final attempt = task.retryCount + 1;
        final delay = c.retryAfterSeconds != null
            ? Duration(seconds: c.retryAfterSeconds!)
            : _backoff.delayForAttempt(attempt);
        // Persist the attempt count first: a budget-exhausted task must show
        // how many failures were seen.
        task = await _save(task.copyWith(
          retryCount: attempt,
          errorKind: c.kind,
          errorMessage: c.message,
        ));
        if (!_backoff.shouldRetry(attempt)) {
          return _fail(task, c.kind,
              'Upload paused after $attempt attempts. You can retry manually. (${c.message})');
        }
        task = await _save(task.copyWith(
          state: UploadTaskState.retryWait,
          errorKind: c.kind,
          errorMessage: c.message,
          nextRetryAt: DateTime.now().add(delay),
        ));
        final ok = await _sleepOrCancel(delay, cancel);
        if (!ok || cancel.isRequested || task.cancelRequested) return task;
        if (!await _canProceed(task)) return _pause(task, 'Paused.');
        // The world may have moved during the wait (another resume path, a
        // completed retry elsewhere): reconcile before resuming, best-effort.
        // If the GET itself fails, the outer loop re-handles from old truth
        // and any stale offset converges via 409.
        try {
          final remote = await _api.getSession(token: token, sessionId: task.sessionId!);
          task = _adoptRemote(task, remote);
          if (task.isTerminal) {
            final terminal = await _save(task);
            return terminal;
          }
        } catch (_) {}
        // uploading → uploading is an allowed self-transition.
        return _save(task.copyWith(state: UploadTaskState.uploading, clearNextRetry: true));
      case UploadAction.reconcileNow:
        UploadTask adopted;
        try {
          final remote = await _api.getSession(token: token, sessionId: task.sessionId!);
          adopted = _adoptRemote(task, remote);
        } catch (re) {
          return _handleError(task, re, bodyWasSent: false, cancel: cancel, token: token);
        }
        final savedAdopted = await _save(adopted);
        return savedAdopted;
      case UploadAction.recreateSession:
        UploadTask recreated;
        try {
          recreated = await _reconcileOrRecreate(task, token);
        } catch (re) {
          return _handleError(task, re, bodyWasSent: false, cancel: cancel, token: token);
        }
        return recreated;
      case UploadAction.markExpired:
        return _save(task.copyWith(
            state: UploadTaskState.expired, errorKind: c.kind, errorMessage: c.message));
      case UploadAction.failPermanent:
        return _fail(task, c.kind, c.message);
    }
  }

  Future<UploadTask> _pause(UploadTask task, String message) async {
    if (task.isTerminal) return task;
    _log(UploadDiagnostic(event: 'paused', taskId: task.taskId, message: message));
    return _save(task.copyWith(
      state: UploadTaskState.paused, errorKind: UploadErrorKind.network, errorMessage: message));
  }

  Future<UploadTask> _fail(UploadTask task, UploadErrorKind kind, String message) async {
    if (task.isTerminal) return task;
    UploadTaskState target = UploadTaskState.failed;
    try {
      return await _save(task.copyWith(state: target, errorKind: kind, errorMessage: message));
    } catch (_) {
      return task; // already terminal through a race; keep truth
    }
  }

  Future<UploadTask> _doCancel(UploadTask task) async {
    if (task.state == UploadTaskState.cancelled) {
      // Flush a previously-failed offline cancel when possible.
      if (task.cancelRequested && task.sessionId != null) {
        final token = await _tokenOrFail(task);
        if (token != null) {
          var flushed = false;
          try {
            await _api.cancelSession(token: token, sessionId: task.sessionId!);
            flushed = true;
          } catch (_) {}
          if (flushed) {
            final cleared = await _save(task.copyWith(cancelRequested: false));
            return cleared;
          }
        }
      }
      return task;
    }
    // Terminal-but-not-cancelled (completed/failed/expired): nothing to cancel.
    if (task.isTerminal) return task;
    task = await _save(task.copyWith(state: UploadTaskState.cancelling));
    _log(UploadDiagnostic(event: 'cancel', taskId: task.taskId, sessionId: task.sessionId));
    if (task.sessionId != null) {
      final token = await _tokenOrFail(task);
      if (token != null) {
        var delivered = false;
        try {
          await _api.cancelSession(token: token, sessionId: task.sessionId!);
          delivered = true;
        } catch (_) {
          // Offline: persist the intent; reconcile flushes it later.
        }
        if (delivered) {
          final done = await _save(task.copyWith(
              state: UploadTaskState.cancelled, cancelRequested: false, clearError: true));
          return done;
        }
        final pending = await _save(
            task.copyWith(state: UploadTaskState.cancelled, cancelRequested: true));
        return pending;
      }
    }
    return _save(task.copyWith(state: UploadTaskState.cancelled, cancelRequested: false, clearError: true));
  }

  /// Interruptable sleep for backoff. Returns false when cancelled.
  Future<bool> _sleepOrCancel(Duration delay, UploadCancellation cancel) async {
    var remaining = delay;
    const slice = Duration(milliseconds: 100);
    while (remaining > Duration.zero) {
      if (cancel.isRequested) return false;
      final step = remaining < slice ? remaining : slice;
      await Future.delayed(step);
      remaining -= step;
    }
    return !cancel.isRequested;
  }

  String? _scope(UploadTask task, String key) {
    final v = task.scope[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  Map<String, dynamic>? _scopeMap(UploadTask task, String key) {
    final v = task.scope[key];
    return v is Map<String, dynamic> ? v : null;
  }
}
