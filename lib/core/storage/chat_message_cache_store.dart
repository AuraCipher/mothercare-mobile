import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/chat/models/chat_models.dart';
import 'app_database.dart';
import 'cache_constants.dart';

class CachedRoomMessages {
  const CachedRoomMessages({
    required this.messages,
    this.cursor,
    this.hasMore = true,
    required this.savedAt,
  });

  final List<ChatMessage> messages;
  final String? cursor;
  final bool hasMore;
  final DateTime savedAt;

  bool isExpired() => DateTime.now().difference(savedAt) > CacheTtls.messageRoom;
}

class ChatMessageCacheStore {
  ChatMessageCacheStore._();

  static final ChatMessageCacheStore instance = ChatMessageCacheStore._();

  static bool testMode = false;

  static const _maxMessagesPerRoom = 200;
  Directory? _baseDir;

  Future<void> _deleteUserFiles(String userId) async {
    try {
      _baseDir ??= await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<CachedRoomMessages?> loadRoom({
    required String userId,
    required String roomId,
  }) async {
    if (testMode) return null;
    try {
      final db = await AppDatabase.instance.database;
      final metaRows = await db.query(
        'chat_room_meta',
        where: 'user_id = ? AND room_id = ?',
        whereArgs: [userId, roomId],
        limit: 1,
      );
      if (metaRows.isEmpty) return null;

      final meta = metaRows.first;
      final savedAtMs = meta['saved_at'] as int?;
      if (savedAtMs == null) return null;

      final messageRows = await db.query(
        'chat_messages',
        where: 'user_id = ? AND room_id = ?',
        whereArgs: [userId, roomId],
        orderBy: 'sort_key ASC',
      );
      final messages = messageRows
          .map((row) => ChatMessage.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              ))
          .toList();

      return CachedRoomMessages(
        messages: messages,
        cursor: meta['cursor'] as String?,
        hasMore: (meta['has_more'] as int? ?? 1) == 1,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRoom({
    required String userId,
    required String roomId,
    required List<ChatMessage> messages,
    String? cursor,
    bool hasMore = true,
  }) async {
    if (testMode) return;
    try {
      final trimmed = messages.length > _maxMessagesPerRoom
          ? messages.sublist(messages.length - _maxMessagesPerRoom)
          : messages;
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.transaction((txn) async {
        await txn.delete(
          'chat_messages',
          where: 'user_id = ? AND room_id = ?',
          whereArgs: [userId, roomId],
        );
        var index = 0;
        for (final message in trimmed) {
          await txn.insert(
            'chat_messages',
            {
              'user_id': userId,
              'room_id': roomId,
              'message_id': message.id,
              'sort_key': index++,
              'payload': jsonEncode(message.toJson()),
              'created_at': message.createdAt.millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.insert(
          'chat_room_meta',
          {
            'user_id': userId,
            'room_id': roomId,
            'cursor': cursor,
            'has_more': hasMore ? 1 : 0,
            'saved_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (_) {}
  }

  Future<void> clearUser(String userId) async {
    if (testMode) return;
    await _deleteUserFiles(userId);
    await AppDatabase.instance.clearUser(userId);
  }
}
