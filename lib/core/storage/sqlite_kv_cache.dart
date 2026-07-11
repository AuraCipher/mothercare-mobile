import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'cached_envelope.dart';

/// Key-value JSON blobs (bootstrap, landing, future dashboard snapshots).
class SqliteKvCache {
  SqliteKvCache._();

  static final SqliteKvCache instance = SqliteKvCache._();

  Future<void> put({
    required String key,
    required String category,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
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

  Future<CachedEnvelope?> get(String key) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'kv_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedEnvelope.parse(rows.first['payload'] as String);
  }

  Future<void> delete(String key) async {
    final db = await AppDatabase.instance.database;
    await db.delete('kv_cache', where: 'cache_key = ?', whereArgs: [key]);
  }
}
