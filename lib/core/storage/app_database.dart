import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single SQLite database for offline dashboard + chat caches.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? testOverride;

  Database? _db;

  Future<Database> get database async {
    if (testOverride != null) return testOverride!;
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    return openDatabase(
      p.join(basePath, 'mcs_app.db'),
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
  }

  Future<void> clearUser(String userId) async {
    final db = await database;
    await db.delete('kv_cache', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('chat_messages', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('chat_room_meta', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('pending_outgoing', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
