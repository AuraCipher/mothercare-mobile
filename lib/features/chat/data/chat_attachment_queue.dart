import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../uploads/resumable_upload_engine.dart' show UploadTokenProvider;
import '../../uploads/upload_scheduler.dart';
import '../../uploads/upload_task.dart';
import '../models/chat_models.dart';
import 'chat_file_api.dart';
import 'chat_socket_service.dart';

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
  })  : _scheduler = scheduler,
        _socket = socket,
        _files = files,
        _getToken = getToken,
        _userId = userId,
        _roomId = roomId,
        _academicYearId = academicYearId,
        _stagingDir = stagingDir {
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
  /// Returns the created message for the list; echo dedupes by id.
  Future<ChatMessage> send({String? caption}) async {
    if (_sending) throw StateError('Send already in progress');
    final ready = completedTasks;
    if (ready.isEmpty || _hasActiveUploads) {
      throw StateError('Attachments are not ready to send');
    }
    final ids = [for (final t in ready) t.fileRecordId!];
    final key = _pendingSend?.clientMessageId ?? newIdempotencyKey();
    _sending = true;
    _pendingSend = PendingSend(clientMessageId: key, fileRecordIds: ids, caption: caption);
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
      notifyListeners();
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Explicit retry of a failed send — SAME clientMessageId (idempotent).
  Future<ChatMessage> retrySend() {
    final pending = _pendingSend;
    if (pending == null || pending.state != PendingSendState.failed) {
      throw StateError('No failed send to retry');
    }
    return send(caption: pending.caption);
  }

  void clearSendError() {
    if (_pendingSend?.state == PendingSendState.failed) {
      _pendingSend = null;
      notifyListeners();
    }
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
  /// (uploads survive the process; the tray rebuilds from task state).
  Future<void> recover() async {
    final tasks = await _scheduler.recover(_userId);
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
    notifyListeners();
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
