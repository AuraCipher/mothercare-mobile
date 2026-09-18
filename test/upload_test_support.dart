import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/app_database.dart';
import 'package:mobile/features/uploads/upload_backoff.dart';
import 'package:mobile/features/uploads/upload_diagnostics.dart';
import 'package:mobile/features/uploads/upload_errors.dart';
import 'package:mobile/features/uploads/upload_session_api.dart';
import 'package:mobile/features/uploads/upload_task.dart';
import 'package:mobile/features/uploads/upload_task_store.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared harness for M3 upload tests: in-memory SQLite, temp files,
/// and a scripted in-memory M1/M2 server.
class TestDb {
  static bool _ffiReady = false;

  static Future<UploadTaskStore> openStore() async {
    if (!_ffiReady) {
      sqfliteFfiInit();
      _ffiReady = true;
    }
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: (db, version) => AppDatabase.createSchema(db),
        onUpgrade: (db, oldVersion, _) => AppDatabase.upgradeSchema(db, oldVersion),
      ),
    );
    AppDatabase.testOverride = db;
    addTearDown(() async {
      AppDatabase.testOverride = null;
      await db.close();
    });
    return UploadTaskStore();
  }
}

Future<File> makeTempFile(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

List<int> patternBytes(int size, int seed) =>
    List<int>.generate(size, (i) => (i * 31 + seed) % 256);

UploadTask makeTask({
  String taskId = 'task-1',
  String userId = 'user-1',
  String key = 'idem-key-1',
  String? sessionId,
  required String localPath,
  int expectedSize = 100,
  int serverBytes = 0,
  UploadTaskState state = UploadTaskState.queued,
  String purpose = 'document',
}) =>
    UploadTask(
      taskId: taskId,
      userId: userId,
      idempotencyKey: key,
      sessionId: sessionId,
      localPath: localPath,
      fileName: 'file.bin',
      mimeType: 'application/octet-stream',
      purpose: purpose,
      expectedSize: expectedSize,
      serverBytes: serverBytes,
      state: state,
    );

/// Scripted in-memory M1/M2 server. Records every PATCH range so tests can
/// prove no byte range was ever sent twice.
class ScriptedUploadApi extends UploadSessionApi {
  ScriptedUploadApi() : super(client: http.Client()); // never used; all methods overridden

  final sessions = <String, _ScriptSession>{};
  final patchRanges = <String, List<({int offset, int length})>>{};
  int _nextId = 0;

  int currentPatchCalls = 0;
  int maxPatchCalls = 0;

  /// Knobs (reset per scenario by tests).
  int dropPatchResponses = 0;
  int failPatchWith = 0;
  int failCreateWith = 0;
  int failCompleteTimes = 0;
  bool failCancel = false;
  Duration patchDelay = Duration.zero;
  String? completeFileRecordId;

  int createCalls = 0;
  int getCalls = 0;
  int completeCalls = 0;
  int cancelCalls = 0;

  /// Idempotency keys whose creation must fail (per-task failure injection).
  final failKeys = <String, int>{};

  /// Pre-seed a server session (e.g. "server ahead of local cache").
  String seedSession({required int expectedSize, int bytesUploaded = 0, String status = 'INITIATED'}) {
    final id = 'sess-${_nextId++}';
    sessions[id] = _ScriptSession(
        id: id, expectedSize: expectedSize, bytesUploaded: bytesUploaded, status: status);
    return id;
  }

  @override
  Future<({RemoteUploadSession session, bool created})> createSession({
    required String token,
    required String purpose,
    required String fileName,
    required String mimeType,
    required int expectedSize,
    required String idempotencyKey,
    String? entityType,
    String? entityId,
    String? roomId,
    String? academicYearId,
    Map<String, dynamic>? metadata,
  }) async {
    createCalls += 1;
    _requireAuth(token);
    if (failKeys.containsKey(idempotencyKey)) {
      throw _http(failKeys[idempotencyKey]!, 'create failed for key');
    }
    if (failCreateWith != 0) throw _http(failCreateWith, 'create failed');
    // Idempotent reuse by key.
    for (final s in sessions.values) {
      if (s.key == idempotencyKey) {
        return (session: s.remote(), created: false);
      }
    }
    final id = 'sess-${_nextId++}';
    sessions[id] = _ScriptSession(
        id: id, expectedSize: expectedSize, bytesUploaded: 0, status: 'INITIATED', key: idempotencyKey);
    return (session: sessions[id]!.remote(), created: true);
  }

  @override
  Future<RemoteUploadSession> getSession({required String token, required String sessionId}) async {
    getCalls += 1;
    _requireAuth(token);
    final s = sessions[sessionId];
    if (s == null) throw _http(404, 'Upload session not found');
    return s.remote();
  }

  @override
  Future<ChunkAck> sendChunk({
    required String token,
    required String sessionId,
    required int offset,
    required List<int> bytes,
    bool Function()? onCancel,
  }) async {
    currentPatchCalls += 1;
    maxPatchCalls = currentPatchCalls > maxPatchCalls ? currentPatchCalls : maxPatchCalls;
    try {
      if (patchDelay > Duration.zero) await Future.delayed(patchDelay);
      _requireAuth(token);
      final s = sessions[sessionId];
      if (s == null) throw _http(404, 'Upload session not found');
      if (s.isTerminal) throw _http(409, 'Upload session is already ${s.status}');
      if (offset != s.bytesUploaded) throw _http(409, 'Stale offset');
      if (failPatchWith != 0) throw _http(failPatchWith, 'patch failed');
      (patchRanges[sessionId] ??= []).add((offset: offset, length: bytes.length));
      s.bytesUploaded += bytes.length;
      if (onCancel != null && onCancel()) {
        // Applied server-side; client ignores the outcome (like a disconnect).
        throw const SocketException('cancelled');
      }
      if (dropPatchResponses > 0) {
        dropPatchResponses -= 1;
        throw const SocketException('connection lost after commit');
      }
      return ChunkAck(
          bytesUploaded: s.bytesUploaded,
          expectedSize: s.expectedSize,
          partNumber: offset ~/ (5 * 1024 * 1024) + 1,
          complete: s.bytesUploaded >= s.expectedSize);
    } finally {
      currentPatchCalls -= 1;
    }
  }

  @override
  Future<({RemoteUploadSession session, bool created, String? fileRecordId})> completeSession({
    required String token,
    required String sessionId,
  }) async {
    completeCalls += 1;
    _requireAuth(token);
    final s = sessions[sessionId];
    if (s == null) throw _http(404, 'Upload session not found');
    if (s.status == 'COMPLETED') {
      return (session: s.remote(), created: false, fileRecordId: s.fileRecordId);
    }
    if (s.bytesUploaded != s.expectedSize) throw _http(409, 'Upload incomplete');
    if (failCompleteTimes > 0) {
      failCompleteTimes -= 1;
      throw const SocketException('complete response lost');
    }
    s.status = 'COMPLETED';
    s.fileRecordId = completeFileRecordId ?? 'file-$sessionId';
    return (session: s.remote(), created: true, fileRecordId: s.fileRecordId);
  }

  @override
  Future<RemoteUploadSession> cancelSession({required String token, required String sessionId}) async {
    cancelCalls += 1;
    _requireAuth(token);
    final s = sessions[sessionId];
    if (s == null) throw _http(404, 'Upload session not found');
    if (failCancel) throw const SocketException('offline');
    if (!s.isTerminal) s.status = 'CANCELLED';
    return s.remote();
  }

  void _requireAuth(String token) {
    if (token.isEmpty || token == 'bad-token') throw _http(401, 'Authentication required');
    if (token == 'forbidden-token') throw _http(403, 'Forbidden');
  }

  Never _http(int status, String message) =>
      throw UploadApiException(message, statusCode: status);
}

class _ScriptSession {
  _ScriptSession({
    required this.id,
    required this.expectedSize,
    required this.bytesUploaded,
    required this.status,
    this.key,
  }) : fileRecordId = null;

  final String id;
  final int expectedSize;
  int bytesUploaded;
  String status;
  final String? key;
  String? fileRecordId;

  bool get isTerminal =>
      status == 'COMPLETED' || status == 'CANCELLED' || status == 'EXPIRED' || status == 'FAILED';

  RemoteUploadSession remote() => RemoteUploadSession(
        id: id,
        status: status,
        expectedSize: expectedSize,
        bytesUploaded: bytesUploaded,
        fileRecordId: fileRecordId,
        fileUrl: fileRecordId == null ? null : '/api/uploads/$fileRecordId',
      );
}

UploadBackoffPolicy fastBackoff() =>
    UploadBackoffPolicy(baseDelay: const Duration(milliseconds: 1), maxDelay: const Duration(milliseconds: 5), maxAttempts: 3);

UploadLogger silentLogger() => UploadLogger(enabled: false);

/// Polls [check] until true or [timeout]; throws on timeout (test failure).
Future<void> waitFor(FutureOr<bool> Function() check,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}
