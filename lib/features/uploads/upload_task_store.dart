import 'package:sqflite/sqflite.dart';

import '../../core/storage/app_database.dart';
import 'upload_task.dart';

/// SQLite persistence for resumable upload tasks. Every mutation is a single
/// upsert keyed by (user_id, task_id); the (user_id, idempotency_key) unique
/// index makes enqueue deduplication race-free. All offsets stored here are
/// a cached hint — the server stays authoritative (see engine).
class UploadTaskStore {
  UploadTaskStore({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  Map<String, dynamic> _row(UploadTask task) {
    final json = task.toJson();
    return {
      'user_id': json['userId'],
      'task_id': json['taskId'],
      'idempotency_key': json['idempotencyKey'],
      'session_id': json['sessionId'],
      'local_path': json['localPath'],
      'file_name': json['fileName'],
      'mime_type': json['mimeType'],
      'purpose': json['purpose'],
      'expected_size': json['expectedSize'],
      'server_bytes': json['serverBytes'],
      'state': json['state'],
      'retry_count': json['retryCount'],
      'error_kind': json['errorKind'],
      'error_message': json['errorMessage'],
      'file_record_id': json['fileRecordId'],
      'file_url': json['fileUrl'],
      'cancel_requested': json['cancelRequested'],
      'next_retry_at': json['nextRetryAt'],
      'scope_json': json['scopeJson'],
      'created_at': json['createdAt'],
      'updated_at': json['updatedAt'],
    };
  }

  UploadTask _fromRow(Map<String, dynamic> row) => UploadTask.fromJson({
        'taskId': row['task_id'],
        'userId': row['user_id'],
        'idempotencyKey': row['idempotency_key'],
        'sessionId': row['session_id'],
        'localPath': row['local_path'],
        'fileName': row['file_name'],
        'mimeType': row['mime_type'],
        'purpose': row['purpose'] ?? 'document',
        'expectedSize': row['expected_size'],
        'serverBytes': row['server_bytes'] ?? 0,
        'state': row['state'],
        'retryCount': row['retry_count'] ?? 0,
        'errorKind': row['error_kind'] ?? 'none',
        'errorMessage': row['error_message'],
        'fileRecordId': row['file_record_id'],
        'fileUrl': row['file_url'],
        'cancelRequested': row['cancel_requested'] ?? 0,
        'scopeJson': row['scope_json'],
        'nextRetryAt': row['next_retry_at'],
        'createdAt': row['created_at'],
        'updatedAt': row['updated_at'],
      });

  Future<void> saveTask(UploadTask task) async {
    final db = await _db;
    await db.insert('upload_tasks', _row(task),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<UploadTask?> getTask(String userId, String taskId) async {
    final db = await _db;
    final rows = await db.query('upload_tasks',
        where: 'user_id = ? AND task_id = ?', whereArgs: [userId, taskId], limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<UploadTask?> getTaskByKey(String userId, String idempotencyKey) async {
    final db = await _db;
    final rows = await db.query('upload_tasks',
        where: 'user_id = ? AND idempotency_key = ?',
        whereArgs: [userId, idempotencyKey],
        limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<UploadTask>> listUserTasks(String userId, {Set<UploadTaskState>? states}) async {
    final db = await _db;
    final where = StringBuffer('user_id = ?');
    final args = <dynamic>[userId];
    if (states != null && states.isNotEmpty) {
      where.write(' AND state IN (${List.filled(states.length, '?').join(',')})');
      args.addAll(states.map((s) => s.name));
    }
    final rows = await db.query('upload_tasks',
        where: where.toString(), whereArgs: args, orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  /// Incomplete tasks eligible for recovery on startup/resume/connectivity.
  Future<List<UploadTask>> listRecoverable(String userId) async {
    final terminal = UploadTaskState.values.where(isUploadTerminal).map((s) => s.name).toSet();
    final all = await listUserTasks(userId);
    return all.where((t) => !terminal.contains(t.state.name)).toList();
  }

  Future<void> deleteTask(String userId, String taskId) async {
    final db = await _db;
    await db.delete('upload_tasks',
        where: 'user_id = ? AND task_id = ?', whereArgs: [userId, taskId]);
  }
}
