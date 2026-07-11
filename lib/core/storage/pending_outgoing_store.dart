import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/chat/models/pending_outgoing_message.dart';
import 'app_database.dart';
import 'chat_message_cache_store.dart';

class PendingOutgoingStore {
  PendingOutgoingStore._();

  static final PendingOutgoingStore instance = PendingOutgoingStore._();

  Directory? _baseDir;

  Future<Directory> _pendingMediaDir(String userId) async {
    _baseDir ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId, 'pending_media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String?> persistMediaFile({
    required String userId,
    required String localId,
    required File source,
  }) async {
    try {
      if (!await source.exists()) return null;
      final dir = await _pendingMediaDir(userId);
      final ext = p.extension(source.path);
      final dest = File(p.join(dir.path, '$localId$ext'));
      await source.copy(dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  Future<List<PendingOutgoingMessage>> loadRoom({
    required String userId,
    required String roomId,
  }) async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'pending_outgoing',
        where: 'user_id = ? AND room_id = ?',
        whereArgs: [userId, roomId],
        orderBy: 'sort_key ASC',
      );
      return rows
          .map((row) => PendingOutgoingMessage.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              ))
          .where((item) => item.localId.isNotEmpty)
          .map(_normalizeRestored)
          .toList();
    } catch (_) {
      return [];
    }
  }

  PendingOutgoingMessage _normalizeRestored(PendingOutgoingMessage item) {
    if (item.phase == PendingSendPhase.failed) return item;
    return item.copyWith(phase: PendingSendPhase.failed, progress: 0);
  }

  Future<void> saveRoom({
    required String userId,
    required String roomId,
    required List<PendingOutgoingMessage> pending,
  }) async {
    try {
      final keep = pending.where((p) => p.phase != PendingSendPhase.sending).toList();
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await txn.delete(
          'pending_outgoing',
          where: 'user_id = ? AND room_id = ?',
          whereArgs: [userId, roomId],
        );
        if (keep.isEmpty) return;
        var index = 0;
        for (final item in keep) {
          await txn.insert(
            'pending_outgoing',
            {
              'user_id': userId,
              'room_id': roomId,
              'local_id': item.localId,
              'sort_key': index++,
              'payload': jsonEncode(item.toJson()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> clearUser(String userId) async {
    await ChatMessageCacheStore.instance.clearUser(userId);
  }
}
