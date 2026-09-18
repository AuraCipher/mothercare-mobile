import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chunk_reader.dart';
import 'resumable_upload_engine.dart';
import 'upload_backoff.dart';
import 'upload_diagnostics.dart';
import 'upload_errors.dart';
import 'upload_session_api.dart';
import 'upload_task.dart';
import 'upload_task_store.dart';

/// Concurrency policy. Defaults sit inside the product requirements
/// (photos/documents 3–5, videos 1–2); one file is always one sequential
/// stream (the M2 protocol forbids concurrent chunks of the same file).
class UploadSchedulerConfig {
  const UploadSchedulerConfig({
    this.photoConcurrency = 4,
    this.videoConcurrency = 1,
    this.resumeStagger = const Duration(milliseconds: 300),
  });

  final int photoConcurrency;
  final int videoConcurrency;
  final Duration resumeStagger;
}

class UploadQueueSummary {
  const UploadQueueSummary({
    required this.active,
    required this.queued,
    required this.serverBytes,
    required this.totalBytes,
  });

  final int active;
  final int queued;
  final int serverBytes;
  final int totalBytes;

  double get progress => totalBytes <= 0 ? 0 : (serverBytes / totalBytes).clamp(0.0, 1.0);
}

/// Central resumable-upload queue. Owns concurrency, connectivity/lifecycle
/// gating, and recovery orchestration; [ResumableUploadEngine] owns the
/// per-file protocol. No chat knowledge — M4 consumes completed tasks via
/// [taskUpdates] / [summary] and the stored `fileRecordId`.
class UploadScheduler {
  UploadScheduler({
    required UploadSessionApi api,
    required UploadTaskStore store,
    required UploadTokenProvider getToken,
    this.config = const UploadSchedulerConfig(),
    UploadErrorClassifier classifier = const UploadErrorClassifier(),
    UploadBackoffPolicy? backoff,
    ChunkReader chunkReader = const ChunkReader(),
    UploadLogger? logger,
  })  : _store = store,
        _logger = logger ?? UploadLogger(),
        _api = api,
        _getToken = getToken,
        _classifier = classifier,
        _backoff = backoff,
        _chunkReader = chunkReader;

  final UploadTaskStore _store;
  final UploadLogger _logger;
  final UploadSessionApi _api;
  final UploadTokenProvider _getToken;
  final UploadErrorClassifier _classifier;
  final UploadBackoffPolicy? _backoff;
  final ChunkReader _chunkReader;
  final UploadSchedulerConfig config;

  late final ResumableUploadEngine _engine = ResumableUploadEngine(
    api: _api,
    store: _store,
    getToken: _getToken,
    classifier: _classifier,
    backoff: _backoff,
    chunkReader: _chunkReader,
    logger: _logger,
    canProceed: (task) async =>
        _online && _foreground && !_disposed && !_userPausedIds.contains(task.taskId),
  );

  /// Test seam: drive tasks with a scripted engine.
  // ignore: avoid_setters_without_getters
  set debugEngine(ResumableUploadEngine engine) => _debugEngine = engine;
  ResumableUploadEngine? _debugEngine;
  ResumableUploadEngine get _driver => _debugEngine ?? _engine;

  final _updates = StreamController<UploadTask>.broadcast();
  final _summaries = StreamController<UploadQueueSummary>.broadcast();

  Stream<UploadTask> get taskUpdates => _updates.stream;
  Stream<UploadQueueSummary> get summary => _summaries.stream;

  final _active = <String>{};
  final _cancelTokens = <String, UploadCancellation>{};
  final _userPausedIds = <String>{};
  final _systemPausedIds = <String>{};
  bool _online = true;
  bool _foreground = true;
  bool _disposed = false;
  bool _pumping = false;
  bool _pumpQueued = false;
  String? _userId;

  /// Enqueue one independent file. Duplicate (userId, idempotencyKey)
  /// submissions return the existing task — duplicate user taps are safe.
  Future<UploadTask> enqueue({
    required String userId,
    required String localPath,
    required String fileName,
    required String mimeType,
    String purpose = 'document',
    String? idempotencyKey,
    Map<String, dynamic>? scope,
  }) async {
    _userId = userId;
    final key = idempotencyKey ?? newIdempotencyKey();
    final existing = await _store.getTaskByKey(userId, key);
    if (existing != null) return existing;

    final file = File(localPath);
    if (!await file.exists()) {
      throw ArgumentError('Local file does not exist: $localPath');
    }
    final size = await file.length();
    if (size <= 0) throw ArgumentError('Local file is empty: $localPath');

    final task = UploadTask(
      taskId: newIdempotencyKey(),
      userId: userId,
      idempotencyKey: key,
      localPath: localPath,
      fileName: fileName,
      mimeType: mimeType,
      purpose: purpose,
      expectedSize: size,
      scopeJson: scope == null ? null : jsonEncode(scope),
    );
    await _store.saveTask(task);
    _emit(task);
    _pump();
    return task;
  }

  Future<void> cancel(String userId, String taskId) async {
    _cancelTokens[taskId]?.request();
    _userPausedIds.remove(taskId);
    _systemPausedIds.remove(taskId);
    final task = await _store.getTask(userId, taskId);
    if (task == null) return;
    if (task.isTerminal) {
      // Flush a persisted offline-cancel intent if present.
      if (task.state == UploadTaskState.cancelled && task.cancelRequested) {
        _emit(await _driver.reconcileTask(task));
      }
      _pump();
      return;
    }
    await _store.saveTask(task.copyWith(cancelRequested: true));
    // If no driver is running it, drive cancellation now.
    if (!_active.contains(taskId)) {
      final latest = (await _store.getTask(userId, taskId)) ?? task;
      _emit(await _driver.runTask(latest));
    }
    _pump();
  }

  /// Explicit user retry. `failed` keeps its idempotency key (server reuse);
  /// `expired` gets a FRESH key (the old server session is unrecoverable).
  Future<UploadTask?> retry(String userId, String taskId) async {
    var task = await _store.getTask(userId, taskId);
    if (task == null) return null;
    _userPausedIds.remove(taskId);
    _systemPausedIds.remove(taskId);
    if (task.state == UploadTaskState.expired) {
      task = UploadTask(
        taskId: task.taskId,
        userId: task.userId,
        idempotencyKey: newIdempotencyKey(),
        localPath: task.localPath,
        fileName: task.fileName,
        mimeType: task.mimeType,
        purpose: task.purpose,
        expectedSize: task.expectedSize,
        scopeJson: task.scopeJson,
      );
    } else if (task.state == UploadTaskState.failed ||
        task.state == UploadTaskState.paused) {
      task = task.copyWith(
          state: UploadTaskState.queued, retryCount: 0, clearError: true, clearNextRetry: true);
    } else {
      return task;
    }
    await _store.saveTask(task);
    _emit(task);
    _pump();
    return task;
  }

  /// User-initiated per-task pause. The running driver (if any) parks itself
  /// at the next chunk boundary via the [canProceed] probe; nothing is
  /// cancelled. Use [retry] to resume (explicit user action).
  Future<void> pauseTask(String userId, String taskId) async {
    final task = await _store.getTask(userId, taskId);
    if (task == null || task.isTerminal) return;
    _userPausedIds.add(taskId);
    if (!_active.contains(taskId)) {
      await _store.saveTask(task.copyWith(state: UploadTaskState.paused));
      _emitSummary();
    }
    _pump();
  }

  /// Drops a task row without touching the server (composer discard paths).
  /// Server-side cancellation, if needed, is the caller's job ([cancel]).
  Future<void> deleteTask(String userId, String taskId) async {
    _userPausedIds.remove(taskId);
    _systemPausedIds.remove(taskId);
    await _store.deleteTask(userId, taskId);
    _emitSummary();
    _pump();
  }

  /// Connectivity is a HINT: stop scheduling; drivers park at the next chunk
  /// boundary (persisting `paused`); resume is staggered to avoid a storm.
  void handleConnectivityLost() {
    if (!_online) return;
    _online = false;
    _systemPausedIds.addAll(_active);
    _logger.log(UploadDiagnostic(event: 'offline', taskId: '-'));
  }

  void handleConnectivityRestored() {
    if (_online) return;
    _online = true;
    _logger.log(UploadDiagnostic(event: 'online', taskId: '-'));
    _resumePaused(stagger: true);
  }

  /// App backgrounded: nothing new starts; in-flight chunks complete or fail
  /// and persist; resume reconciles everything from the server.
  void handleAppPaused() {
    _foreground = false;
    _systemPausedIds.addAll(_active);
    _logger.log(UploadDiagnostic(event: 'background', taskId: '-'));
  }

  void handleAppResumed() {
    _foreground = true;
    _logger.log(UploadDiagnostic(event: 'foreground', taskId: '-'));
    _resumePaused(stagger: true);
  }

  /// Startup / login recovery: load incomplete tasks, validate + reconcile
  /// each against the server, and requeue what's eligible. User-paused tasks
  /// stay paused (explicit resume only). Never assumes the last HTTP request
  /// completed.
  Future<List<UploadTask>> recover(String userId) async {
    _userId = userId;
    final tasks = await _store.listRecoverable(userId);
    final out = <UploadTask>[];
    for (final task in tasks) {
      try {
        var reconciled = await _driver.reconcileTask(task);
        _emit(reconciled);
        if (!reconciled.isTerminal && reconciled.state != UploadTaskState.paused) {
          if (reconciled.state != UploadTaskState.queued) {
            reconciled = reconciled.copyWith(state: UploadTaskState.queued, clearError: true);
            await _store.saveTask(reconciled);
            _emit(reconciled);
          }
        }
        out.add(reconciled);
      } catch (_) {
        out.add(task); // offline at boot: stays queued/paused, resumes later
      }
    }
    _pump();
    return out;
  }

  void _resumePaused({required bool stagger}) async {
    final userId = _userId;
    if (userId == null || _disposed) return;
    final tasks = await _store.listUserTasks(userId, states: {UploadTaskState.paused});
    var delay = Duration.zero;
    // Only system-parked tasks auto-resume; user-paused tasks wait for retry().
    for (final task in tasks.where((t) => !_userPausedIds.contains(t.taskId))) {
      if (stagger && delay > Duration.zero) await Future.delayed(delay);
      if (_disposed) return;
      await _store.saveTask(task.copyWith(state: UploadTaskState.queued, clearError: true));
      _systemPausedIds.remove(task.taskId);
      delay += config.resumeStagger;
    }
    _pump();
  }

  void _pump() {
    if (_disposed || !_online || !_foreground) return;
    final userId = _userId;
    if (userId == null) return;
    if (_pumping) {
      _pumpQueued = true; // a completion raced us; re-scan when current pass ends
      return;
    }
    _pumping = true;
    unawaited(_pumpAsync(userId).whenComplete(() {
      _pumping = false;
      if (_pumpQueued && !_disposed) {
        _pumpQueued = false;
        _pump();
      }
    }));
  }

  Future<void> _pumpAsync(String userId) async {
    if (_disposed || !_online || !_foreground) return;
    try {
      await _pumpScan(userId);
    } catch (_) {
      // Transient store failure (lock, teardown race): leave tasks queued;
      // the next pump trigger retries. Never crash the queue on a read.
    }
  }

  Future<void> _pumpScan(String userId) async {
    final queued = await _store.listUserTasks(userId, states: {UploadTaskState.queued});
    if (queued.isEmpty) {
      _emitSummary();
      return;
    }
    // Snapshot: completions mutate [_active] concurrently with this scan.
    final activeIds = Set<String>.of(_active);
    var photoActive = 0, videoActive = 0;
    for (final id in activeIds) {
      final t = await _store.getTask(userId, id);
      if (t == null) continue;
      if (t.isVideo) {
        videoActive += 1;
      } else {
        photoActive += 1;
      }
    }
    var photoSlots = config.photoConcurrency - photoActive;
    var videoSlots = config.videoConcurrency - videoActive;
    for (final task in queued) {
      if (_disposed || !_online || !_foreground) break;
      if (_active.contains(task.taskId)) continue;
      if (task.isVideo) {
        if (videoSlots <= 0) continue;
        videoSlots -= 1;
      } else {
        if (photoSlots <= 0) continue;
        photoSlots -= 1;
      }
      _launch(task);
    }
    _emitSummary();
  }

  void _launch(UploadTask task) {
    final token = UploadCancellation();
    _cancelTokens[task.taskId] = token;
    _active.add(task.taskId);
    _driver.runTask(task, cancel: token).then((done) {
      _active.remove(task.taskId);
      _cancelTokens.remove(task.taskId);
      _systemPausedIds.remove(task.taskId);
      _emit(done);
      _pump();
    }).catchError((Object _) {
      _active.remove(task.taskId);
      _cancelTokens.remove(task.taskId);
      _systemPausedIds.remove(task.taskId);
      _pump();
    });
  }

  void _emit(UploadTask task) {
    if (!_updates.isClosed) _updates.add(task);
    _emitSummary();
  }

  void _emitSummary() {
    if (_summaries.isClosed || _disposed) return;
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    unawaited(_store.listUserTasks(userId).then((tasks) {
      var active = 0, queued = 0, bytes = 0, total = 0;
      for (final t in tasks) {
        if (t.isTerminal) continue;
        if (_active.contains(t.taskId)) {
          active += 1;
        } else {
          queued += 1;
        }
        bytes += t.serverBytes;
        total += t.expectedSize;
      }
      if (!_summaries.isClosed) {
        _summaries.add(UploadQueueSummary(
            active: active, queued: queued, serverBytes: bytes, totalBytes: total));
      }
    }).catchError((Object _) {}));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final token in _cancelTokens.values) {
      token.request();
    }
    await _updates.close();
    await _summaries.close();
    _engine.dispose();
    _debugEngine?.dispose();
  }
}
