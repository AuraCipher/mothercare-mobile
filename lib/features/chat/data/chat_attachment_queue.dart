import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../uploads/resumable_upload_engine.dart' show UploadTokenProvider;
import '../../uploads/upload_scheduler.dart';
import '../../uploads/upload_task.dart';
import '../../uploads/upload_task_store.dart';
import '../../../core/api/api_exception.dart';
import '../models/chat_models.dart';
import 'chat_api.dart';
import 'chat_file_api.dart';
import 'chat_socket_service.dart';
import 'chat_staging_gc.dart';
import 'send_intent_store.dart';

/// Bulk selection limits (§7): photos+videos combined, videos subset.
const int maxBulkMediaTotal = 100;
const int maxBulkVideos = 10;

class AttachmentLimitException implements Exception {
  AttachmentLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One composer attachment. Progress/state come ONLY from the M3 [UploadTask]
/// snapshot (single source of truth); this object adds chat concerns:
/// stable selection order, kind label, and staged preview path.
class QueuedAttachment {
  QueuedAttachment({
    required this.taskId,
    required this.sortIndex,
    required this.kind,
    required this.fileName,
  });

  final String taskId;
  final int sortIndex;
  final String kind; // image | video | document | voice
  final String fileName;
}

/// Send-state for the composer's message attempt (separate from uploads).
enum PendingSendState { idle, sending, failed }

class PendingSend {
  PendingSend({
    required this.clientMessageId,
    required this.fileRecordIds,
    this.caption,
    this.state = PendingSendState.sending,
    this.error,
    this.uncertain = false,
  });

  final String clientMessageId;
  final List<String> fileRecordIds;
  final String? caption;
  PendingSendState state;
  String? error;
  bool uncertain;
}

/// Per-room chat attachment controller. Owns selection → M3 tasks → tray
/// state → socket send. Never uploads bytes itself (M3 owns that); never
/// renders (the tray widget observes via [ChangeNotifier]).
class ChatAttachmentQueue extends ChangeNotifier {
  ChatAttachmentQueue({
    required UploadScheduler scheduler,
    required ChatSocketService socket,
    required ChatFileApi files,
    required UploadTokenProvider getToken,
    required String userId,
    required String roomId,
    required String academicYearId,
    Directory? stagingDir,
    ChatApi? chatApi,
    SendIntentStore? intents,
  })  : _scheduler = scheduler,
        _socket = socket,
        _files = files,
        _getToken = getToken,
        _userId = userId,
        _roomId = roomId,
        _academicYearId = academicYearId,
        _stagingDir = stagingDir,
        _chatApi = chatApi ?? ChatApi(),
        _intents = intents ?? SendIntentStore() {
    _taskSub = _scheduler.taskUpdates.listen(_onTaskUpdate);
  }

  final UploadScheduler _scheduler;
  final ChatSocketService _socket;
  final ChatFileApi _files;
  final UploadTokenProvider _getToken;
  final String _userId;
  final String _roomId;
  final String _academicYearId;
  /// Test seam: avoids path_provider (no platform channels in unit tests).
  final Directory? _stagingDir;
  final ChatApi _chatApi;
  final SendIntentStore _intents;

  final _items = <String, QueuedAttachment>{}; // taskId -> item
  final _tasks = <String, UploadTask>{}; // taskId -> latest M3 snapshot
  int _sortCounter = 0;
  PendingSend? _pendingSend;
  bool _sending = false;
  late final StreamSubscription<UploadTask> _taskSub;
  bool _disposed = false;

  /// Selection-ordered tray items with their live M3 snapshots.
  List<({QueuedAttachment item, UploadTask? task})> get tray {
    final list = _items.values.toList()..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return [for (final item in list) (item: item, task: _tasks[item.taskId])];
  }

  PendingSend? get pendingSend => _pendingSend;
  bool get isSending => _sending;
  bool get isEmpty => _items.isEmpty;

  int get _mediaCount =>
      _items.values.where((i) => i.kind == 'image' || i.kind == 'video').length;
  int get _videoCount => _items.values.where((i) => i.kind == 'video').length;

  void _onTaskUpdate(UploadTask task) {
    if (!_items.containsKey(task.taskId)) return;
    _tasks[task.taskId] = task;
    if (!_disposed) notifyListeners();
  }

  void _checkBulkLimits({required int addImages, required int addVideos}) {
    final total = _mediaCount + addImages + addVideos;
    if (total > maxBulkMediaTotal) {
      throw AttachmentLimitException(
          'You can select up to $maxBulkMediaTotal photos/videos (would be $total).');
    }
    if (_videoCount + addVideos > maxBulkVideos) {
      throw AttachmentLimitException(
          'You can select up to $maxBulkVideos videos in one batch.');
    }
  }

  /// Stage a picked file into the user-scoped cache (auto-wiped on logout
  /// with the rest of mcs_chat_cache) and enqueue an M3 task for it.
  Future<QueuedAttachment> _stageAndEnqueue({
    required File source,
    required String fileName,
    required String mimeType,
    required String purpose,
    required String kind,
    Map<String, dynamic>? metadata,
  }) async {
    final Directory dir;
    if (_stagingDir != null) {
      dir = Directory(p.join(_stagingDir.path, 'mcs_chat_cache', _userId, 'chat_uploads'));
      await dir.create(recursive: true);
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(docs.path, 'mcs_chat_cache', _userId, 'chat_uploads'));
      await dir.create(recursive: true);
    }
    final ext = p.extension(fileName);
    final staged = File(p.join(dir.path, '${newIdempotencyKey()}$ext}'));
    await source.copy(staged.path);

    final sortIndex = _sortCounter++;
    final task = await _scheduler.enqueue(
      userId: _userId,
      localPath: staged.path,
      fileName: fileName,
      mimeType: mimeType,
      purpose: purpose,
      scope: {
        'roomId': _roomId,
        'academicYearId': _academicYearId,
        'sortIndex': sortIndex,
        'kind': kind,
        'metadata': ?metadata,
      },
    );
    final item = QueuedAttachment(
        taskId: task.taskId, sortIndex: sortIndex, kind: kind, fileName: fileName);
    _items[task.taskId] = item;
    _tasks[task.taskId] = task;
    notifyListeners();
    return item;
  }

  /// Bulk photos (e.g. pickMultiImage). Order preserved via sortIndex.
  Future<List<QueuedAttachment>> attachPhotos(
    List<({File file, String name, String? mime})> photos,
  ) async {
    if (photos.isEmpty) return [];
    _checkBulkLimits(addImages: photos.length, addVideos: 0);
    final out = <QueuedAttachment>[];
    for (final photo in photos) {
      out.add(await _stageAndEnqueue(
        source: photo.file,
        fileName: photo.name,
        mimeType: photo.mime ?? 'image/jpeg',
        purpose: 'chat',
        kind: 'image',
      ));
    }
    return out;
  }

  Future<QueuedAttachment> attachVideo({
    required File file,
    required String fileName,
    required double durationSeconds,
    String mimeType = 'video/mp4',
  }) async {
    _checkBulkLimits(addImages: 0, addVideos: 1);
    return _stageAndEnqueue(
      source: file,
      fileName: fileName,
      mimeType: mimeType,
      purpose: 'video',
      kind: 'video',
      metadata: {'durationSeconds': durationSeconds},
    );
  }

  Future<QueuedAttachment> attachDocument({
    required File file,
    required String fileName,
    required String mimeType,
  }) async {
    return _stageAndEnqueue(
      source: file,
      fileName: fileName,
      mimeType: mimeType,
      purpose: 'chat',
      kind: 'document',
    );
  }

  Future<QueuedAttachment> attachVoice({
    required File file,
    required String fileName,
    required double durationSeconds,
  }) async {
    return _stageAndEnqueue(
      source: file,
      fileName: fileName,
      mimeType: 'audio/mp4',
      purpose: 'voice_note',
      kind: 'voice',
      metadata: {'durationSeconds': durationSeconds},
    );
  }

  /// Completed attachments in selection order (send candidates).
  List<UploadTask> get completedTasks {
    final list = [
      for (final item in _items.values)
        if (_tasks[item.taskId]?.state == UploadTaskState.completed) _tasks[item.taskId]!
    ];
    list.sort((a, b) => _items[a.taskId]!.sortIndex.compareTo(_items[b.taskId]!.sortIndex));
    return list;
  }

  bool get _hasActiveUploads => _tasks.values.any((t) =>
      t.state == UploadTaskState.queued ||
      t.state == UploadTaskState.creatingSession ||
      t.state == UploadTaskState.ready ||
      t.state == UploadTaskState.uploading ||
      t.state == UploadTaskState.retryWait ||
      t.state == UploadTaskState.completing);

  /// Send is available only when settled with ≥1 completed upload (§11/§18):
  /// never references in-flight files, never fabricates FileRecord ids.
  bool get canSend => !_sending && !_hasActiveUploads && completedTasks.isNotEmpty;

  /// Human-readable composer status (uploading x/y, failed count…).
  String statusText() {
    if (_items.isEmpty) return '';
    final done = completedTasks.length;
    if (_hasActiveUploads) {
      var bytes = 0, total = 0;
      for (final t in _tasks.values) {
        bytes += t.serverBytes;
        total += t.expectedSize;
      }
      final pct = total == 0 ? 0 : (bytes * 100 / total).round();
      return 'Uploading $done/${_items.length} · $pct%';
    }
    final failed = _tasks.values
        .where((t) =>
            t.state == UploadTaskState.failed || t.state == UploadTaskState.expired)
        .length;
    if (failed > 0 && done > 0) return '$done ready · $failed failed';
    if (failed > 0) return '$failed upload${failed == 1 ? '' : 's'} failed';
    return '$done uploaded';
  }

  /// Sends ONE message referencing the completed attachments in selection
  /// order (§17). Retries reuse the same clientMessageId (server dedupes).
  /// M5: the intent is durable (survives kill/restart), media must be READY
  /// (gated via meta poll), and an adopted prior intent reconciles first.
  /// Returns the created message for the list; echo dedupes by id.
  Future<ChatMessage> send({String? caption}) async {
    if (_sending) throw StateError('Send already in progress');
    final ready = completedTasks;
    if (ready.isEmpty || _hasActiveUploads) {
      throw StateError('Attachments are not ready to send');
    }
    final ids = [for (final t in ready) t.fileRecordId!];
    // M5 gating: every file must be processing-READY, not merely uploaded.
    await _waitForMediaReady(ids);
    // Adopt a prior uncertain intent for the same file set (restart recovery)
    // and reconcile it before emitting anything new.
    var key = _pendingSend?.clientMessageId ?? await _adoptMatchingIntent(ids);
    if (key != null) {
      final reconciled = await _reconcileKey(key, ids);
      if (reconciled != null) return reconciled;
    }
    key ??= newIdempotencyKey();
    _sending = true;
    _pendingSend = PendingSend(clientMessageId: key, fileRecordIds: ids, caption: caption);
    await _persistIntent(SendIntentState.sending, key, ids, caption, null, false);
    notifyListeners();
    try {
      final res = await _socket.sendMessageWithAck(
        roomId: _roomId,
        content: caption,
        type: _messageTypeFor(ready),
        mediaFileId: ids.first,
        mediaFileIds: ids,
        clientMessageId: key,
      );
      final message = ChatMessage.fromSocket(res['message'] as Map<String, dynamic>);
      // Success (fresh or duplicate replay): detach sent items, drop staged files.
      for (final t in ready) {
        await _dropTask(t.taskId, deleteStaged: true);
      }
      _pendingSend = null;
      await _intents.deleteIntent(_userId, _roomId, key);
      notifyListeners();
      return message;
    } on ChatSendException catch (e) {
      _pendingSend = PendingSend(
        clientMessageId: key,
        fileRecordIds: ids,
        caption: caption,
        state: PendingSendState.failed,
        error: e.message,
        uncertain: e.uncertain,
      );
      await _persistIntent(
          e.uncertain ? SendIntentState.uncertain : SendIntentState.failed,
          key, ids, caption, e.message, e.uncertain);
      notifyListeners();
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Explicit retry of a failed send — SAME clientMessageId (idempotent).
  /// After a restart the key is restored from the persisted intent whose
  /// file set matches the current tray (never a mismatched key).
  Future<ChatMessage> retrySend() async {
    var pending = _pendingSend;
    if (pending == null || pending.state != PendingSendState.failed) {
      final currentIds = {
        for (final t in completedTasks) t.fileRecordId!,
      };
      final intents = await _intents.listRoomIntents(_userId, _roomId);
      SendIntent? match;
      for (final intent in intents) {
        if (intent.state != SendIntentState.failed &&
            intent.state != SendIntentState.uncertain) {
          continue;
        }
        final intentIds = intent.fileRecordIds.toSet();
        if (intentIds.length == currentIds.length && intentIds.containsAll(currentIds)) {
          match = intent;
          break;
        }
      }
      if (match == null) throw StateError('No failed send to retry');
      pending = PendingSend(
        clientMessageId: match.clientMessageId,
        fileRecordIds: match.fileRecordIds,
        caption: match.caption,
        state: PendingSendState.failed,
        error: match.error,
        uncertain: match.uncertain,
      );
      _pendingSend = pending;
      notifyListeners();
    }
    return send(caption: pending.caption);
  }

  void clearSendError() {
    if (_pendingSend?.state == PendingSendState.failed) {
      _pendingSend = null;
      notifyListeners();
    }
  }

  /// Files the server refused to process (reason per taskId). In-memory —
  /// re-derived on every send attempt, so restarts converge identically.
  final _rejectedFiles = <String, String>{};
  String? rejectedReason(String taskId) => _rejectedFiles[taskId];

  Future<void> _persistIntent(
    SendIntentState state,
    String key,
    List<String> ids,
    String? caption,
    String? error,
    bool uncertain,
  ) async {
    try {
      final existing = await _intents.loadIntent(_userId, _roomId, key);
      await _intents.saveIntent(
        _userId,
        SendIntent(
          clientMessageId: key,
          roomId: _roomId,
          fileRecordIds: ids,
          caption: caption,
          state: state,
          retryCount: (existing?.retryCount ?? 0) + 1,
          error: error,
          uncertain: uncertain,
          createdAt: existing?.createdAt,
        ),
      );
    } catch (_) {}
  }

  /// Restart recovery: an uncertain/sending intent for the same file set
  /// means a previous send may have landed — adopt its key.
  Future<String?> _adoptMatchingIntent(List<String> ids) async {
    try {
      final intents = await _intents.listRoomIntents(_userId, _roomId);
      final wanted = ids.toSet();
      for (final intent in intents) {
        if (intent.state != SendIntentState.sending &&
            intent.state != SendIntentState.uncertain) {
          continue;
        }
        final have = intent.fileRecordIds.toSet();
        if (have.length == wanted.length && have.containsAll(wanted)) {
          return intent.clientMessageId;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Reconcile an adopted key: returns the message if the server already
  /// has it (adopt + detach like a fresh success), else null to proceed.
  Future<ChatMessage?> _reconcileKey(String key, List<String> ids) async {
    try {
      final token = await _getToken();
      if (token == null) return null;
      final found = await _chatApi.fetchMessageByClientKey(
        token: token,
        roomId: _roomId,
        clientMessageId: key,
      );
      if (found == null) return null;
      // Landed earlier: detach the now-sent tray tasks by fileRecordId.
      for (final entry in tray) {
        final task = entry.task;
        if (task?.fileRecordId != null && ids.contains(task!.fileRecordId)) {
          await _dropTask(entry.item.taskId, deleteStaged: true);
        }
      }
      await _intents.deleteIntent(_userId, _roomId, key);
      _pendingSend = null;
      notifyListeners();
      return found;
    } catch (_) {
      return null;
    }
  }

  /// M5 send gating: every file must be processing-READY, not merely
  /// uploaded. Polls meta with backoff (bounded); REJECTED/FAILED aborts
  /// the send with a per-file reason surfaced in the tray.
  Future<void> _waitForMediaReady(List<String> fileRecordIds) async {
    final token = await _getToken();
    if (token == null) throw StateError('Not signed in. Please sign in again.');
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    final pending = Set<String>.of(fileRecordIds);
    var delay = Duration.zero;
    while (pending.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Media is still processing. Please try sending again.');
      }
      if (delay > Duration.zero) await Future.delayed(delay);
      delay = delay == Duration.zero
          ? const Duration(seconds: 2)
          : (delay * 2 > const Duration(seconds: 10) ? const Duration(seconds: 10) : delay * 2);
      for (final id in pending.toList()) {
        Map<String, dynamic> meta;
        try {
          meta = await _files.getFileMeta(token: token, fileId: id);
        } on ApiException catch (e) {
          // 410 Gone = owner-visible policy rejection (converges polling);
          // anything else is transport noise → keep polling until deadline.
          if (e.statusCode == 410) {
            _markRejected(id, e.message.isNotEmpty ? e.message : 'This file was rejected.');
            throw StateError(_rejectedFiles.values.last);
          }
          continue;
        } catch (_) {
          throw StateError('Could not verify media. Please try again.');
        }
        final status = meta['processingStatus'] as String?;
        if (status == null || status == 'READY') {
          pending.remove(id);
        } else if (status == 'REJECTED' || status == 'FAILED') {
          final reason = (meta['processingError'] as String?)?.isNotEmpty == true
              ? meta['processingError'] as String
              : 'This file was rejected.';
          _markRejected(id, reason);
          throw StateError(reason);
        }
        // PENDING/PROCESSING → keep polling.
      }
    }
  }

  void _markRejected(String fileRecordId, String reason) {
    for (final entry in tray) {
      if (entry.task?.fileRecordId == fileRecordId) {
        _rejectedFiles[entry.item.taskId] = reason;
      }
    }
    notifyListeners();
  }

  /// Remove semantics (§27): uploading → M3 cancel; completed-unsent →
  /// owner-delete the server FileRecord (safe: just created, never sent);
  /// failed/cancelled → drop locally. Staged copies always deleted.
  Future<void> removeAttachment(String taskId) async {
    _items.remove(taskId);
    final task = _tasks.remove(taskId);
    notifyListeners();
    if (task == null) return;
    final isActive = task.state == UploadTaskState.uploading ||
        task.state == UploadTaskState.queued ||
        task.state == UploadTaskState.retryWait ||
        task.state == UploadTaskState.creatingSession ||
        task.state == UploadTaskState.ready;
    if (isActive) {
      try {
        await _scheduler.cancel(_userId, taskId);
      } catch (_) {}
    }
    if (task.state == UploadTaskState.completed && task.fileRecordId != null) {
      // Completed but never sent: safe owner cleanup of our own orphan.
      try {
        final token = await _getToken();
        if (token != null) {
          await _files.deleteFile(token: token, fileId: task.fileRecordId!);
        }
      } catch (_) {}
    }
    try {
      await _scheduler.deleteTask(_userId, taskId);
    } catch (_) {}
    await _deleteStaged(task.localPath);
  }

  Future<void> retryAttachment(String taskId) => _scheduler.retry(_userId, taskId);

  Future<void> _dropTask(String taskId, {required bool deleteStaged}) async {
    _items.remove(taskId);
    final task = _tasks.remove(taskId);
    if (task == null) return;
    try {
      await _scheduler.deleteTask(_userId, taskId);
    } catch (_) {}
    if (deleteStaged) await _deleteStaged(task.localPath);
  }

  Future<void> _deleteStaged(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Restart/login recovery: adopt this room's tasks from the M3 store
  /// (uploads survive the process; the tray rebuilds from task state),
  /// then reconcile persisted send intents: uncertain sends that landed
  /// detach their tray tasks; failed ones restore the retry affordance.
  /// Finishes with bounded staged-file GC (never touches live work).
  Future<void> recover() async {
    final tasks = await _scheduler.recover(_userId);
    // Completed/failed uploads are terminal for the M3 driver (recover skips
    // them) but the tray still owns them: completed-unsent stay sendable,
    // failed stay retryable.
    try {
      tasks.addAll(await _scheduler.listTasks(
        _userId,
        states: {UploadTaskState.completed, UploadTaskState.failed},
      ));
    } catch (_) {}
    var maxSort = _sortCounter;
    for (final task in tasks) {
      final scope = task.scope;
      if (scope['roomId'] != _roomId) continue;
      final kind = scope['kind'] as String? ?? _kindFor(task);
      final sortIndex = (scope['sortIndex'] as int?) ?? maxSort++;
      _items[task.taskId] = QueuedAttachment(
        taskId: task.taskId,
        sortIndex: sortIndex,
        kind: kind,
        fileName: task.fileName,
      );
      _tasks[task.taskId] = task;
    }
    if (maxSort > _sortCounter) _sortCounter = maxSort;
    await _reconcilePersistedIntents();
    await _collectGarbage();
    notifyListeners();
  }

  /// Bounded staged-file GC (M5 §30): never touches in-flight work,
  /// never leaves the user dir, never throws.
  Future<void> _collectGarbage() async {
    try {
      final Directory base;
      if (_stagingDir case final stagingDir?) {
        base = stagingDir;
      } else {
        final docs = await getApplicationDocumentsDirectory();
        base = Directory(docs.path);
      }
      final userDir = Directory(p.join(base.path, 'mcs_chat_cache', _userId));
      await const ChatStagingGC().collect(
        userCacheDir: userDir,
        store: UploadTaskStore(),
        userId: _userId,
      );
    } catch (_) {}
  }

  Future<void> _reconcilePersistedIntents() async {
    List<SendIntent> intents;
    try {
      intents = await _intents.listRoomIntents(_userId, _roomId);
    } catch (_) {
      return;
    }
    final token = await _getToken();
    for (final intent in intents) {
      if (intent.state == SendIntentState.failed) {
        // Restore the retry affordance if its files are still in the tray.
        final currentIds = {
          for (final t in completedTasks) t.fileRecordId!,
        };
        final want = intent.fileRecordIds.toSet();
        if (want.length == currentIds.length && want.containsAll(currentIds)) {
          _pendingSend = PendingSend(
            clientMessageId: intent.clientMessageId,
            fileRecordIds: intent.fileRecordIds,
            caption: intent.caption,
            state: PendingSendState.failed,
            error: intent.error,
            uncertain: intent.uncertain,
          );
        }
        continue;
      }
      if (token == null) continue;
      // SENDING/UNCERTAIN: ask the server whether it landed.
      ChatMessage? found;
      try {
        found = await _chatApi.fetchMessageByClientKey(
          token: token,
          roomId: _roomId,
          clientMessageId: intent.clientMessageId,
        );
      } catch (_) {
        continue; // offline: keep the intent for the next resume
      }
      if (found != null) {
        for (final entry in tray.toList()) {
          final task = entry.task;
          if (task?.fileRecordId != null &&
              intent.fileRecordIds.contains(task!.fileRecordId)) {
            await _dropTask(entry.item.taskId, deleteStaged: true);
          }
        }
        await _intents.deleteIntent(_userId, _roomId, intent.clientMessageId);
      }
      // Not found: intent stays; the next send() adopts its key.
    }
  }

  String _kindFor(UploadTask task) {
    if (task.purpose == 'video') return 'video';
    if (task.purpose == 'voice_note') return 'voice';
    final mime = task.mimeType;
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'voice';
    return 'document';
  }

  String _messageTypeFor(List<UploadTask> ready) {
    if (ready.length == 1) {
      final t = ready.single;
      if (t.purpose == 'video') return 'video';
      if (t.purpose == 'voice_note') return 'voice_note';
      if (t.mimeType.startsWith('image/')) return 'image';
      return 'document';
    }
    final kinds = ready.map((t) {
      if (t.purpose == 'video' || t.mimeType.startsWith('video/')) return 'video';
      if (t.mimeType.startsWith('image/')) return 'image';
      return 'other';
    }).toSet();
    if (kinds.length == 1 && kinds.single == 'image') return 'image';
    if (kinds.length == 1 && kinds.single == 'video') return 'video';
    return 'document';
  }

  @override
  void dispose() {
    _disposed = true;
    _taskSub.cancel();
    super.dispose();
  }
}
