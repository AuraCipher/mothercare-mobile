import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'cached_envelope.dart';

/// Key-value JSON blobs (bootstrap, landing, future dashboard snapshots).
class SqliteKvCache {
  SqliteKvCache._();

  static final SqliteKvCache instance = SqliteKvCache._();

  static bool testMode = false;

  Future<void> put({
    required String key,
    required String category,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    if (testMode) return;
    final db = await AppDatabase.instance.database;
    await db.insert(
      'kv_cache',
      {
        'cache_key': key,
        'category': category,
        'user_id': userId,
        'payload': jsonEncode(CachedEnvelope.wrap(data)),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// M9: when [userId] is given, only that user's row may be read.
  /// Unscoped reads exist only for logged-out/legacy fallbacks.
  Future<CachedEnvelope?> get(String key, {String? userId}) async {
    if (testMode) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'kv_cache',
      where: userId == null ? 'cache_key = ?' : 'cache_key = ? AND user_id = ?',
      whereArgs: userId == null ? [key] : [key, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedEnvelope.parse(rows.first['payload'] as String);
  }

  Future<void> delete(String key) async {
    if (testMode) return;
    final db = await AppDatabase.instance.database;
    await db.delete('kv_cache', where: 'cache_key = ?', whereArgs: [key]);
  }

  /// M9: purge every kv row that does not belong to [userId].
  /// Called on login so a previous device user's cached data (e.g. after an
  /// app kill without logout) can never be read by the new login.
  Future<void> deleteAllExceptUser(String userId) async {
    if (testMode) return;
    final db = await AppDatabase.instance.database;
    await db.delete('kv_cache', where: 'user_id != ?', whereArgs: [userId]);
  }
}
