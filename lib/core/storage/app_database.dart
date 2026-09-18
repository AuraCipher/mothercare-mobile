import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single SQLite database for offline dashboard + chat caches.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? testOverride;

  /// Current schema version. v2 adds `upload_tasks` (M3 resumable uploads).
  static const int schemaVersion = 2;

  Database? _db;

  Future<Database> get database async {
    if (testOverride != null) return testOverride!;
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<void> createUploadTasksTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE upload_tasks (
        user_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        session_id TEXT,
        local_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        purpose TEXT NOT NULL DEFAULT 'document',
        expected_size INTEGER NOT NULL,
        server_bytes INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_kind TEXT,
        error_message TEXT,
        file_record_id TEXT,
        file_url TEXT,
        cancel_requested INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER,
        scope_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, task_id)
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_upload_tasks_idem ON upload_tasks(user_id, idempotency_key)',
    );
    await db.execute(
      'CREATE INDEX idx_upload_tasks_state ON upload_tasks(user_id, state)',
    );
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    return openDatabase(
      p.join(basePath, 'mcs_app.db'),
      version: schemaVersion,
      onCreate: (db, version) async => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async =>
          upgradeSchema(db, oldVersion),
    );
  }

  /// Shared schema setup (also used by tests opening their own database).
  static Future<void> createSchema(DatabaseExecutor db) async {
        await db.execute('''
          CREATE TABLE kv_cache (
            cache_key TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            user_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_kv_cache_user ON kv_cache(user_id, category)',
        );

        await db.execute('''
          CREATE TABLE chat_messages (
            user_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            sort_key INTEGER NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (user_id, room_id, message_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_chat_messages_room ON chat_messages(user_id, room_id, sort_key)',
        );

        await db.execute('''
          CREATE TABLE chat_room_meta (
            user_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            cursor TEXT,
            has_more INTEGER NOT NULL DEFAULT 1,
            saved_at INTEGER NOT NULL,
            PRIMARY KEY (user_id, room_id)
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_outgoing (
            user_id TEXT NOT NULL,
            room_id TEXT NOT NULL,
            local_id TEXT NOT NULL,
            sort_key INTEGER NOT NULL,
            payload TEXT NOT NULL,
            PRIMARY KEY (user_id, room_id, local_id)
          )
        ''');

        await createUploadTasksTable(db);
  }

  /// Shared upgrade path (also used by tests).
  static Future<void> upgradeSchema(DatabaseExecutor db, int oldVersion) async {
    if (oldVersion < 2) {
      await createUploadTasksTable(db);
    }
  }

  Future<void> clearUser(String userId) async {
    final db = await database;
    await db.delete('kv_cache', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('chat_messages', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('chat_room_meta', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('pending_outgoing', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('upload_tasks', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
