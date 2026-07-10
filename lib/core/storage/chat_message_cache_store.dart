import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/chat/models/chat_models.dart';
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

  static const _maxMessagesPerRoom = 200;

  Directory? _baseDir;

  Future<Directory> _userDir(String userId) async {
    _baseDir ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId, 'rooms'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _roomFileName(String roomId) => '${_safeId(roomId)}.json';

  String _safeId(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<CachedRoomMessages?> loadRoom({
    required String userId,
    required String roomId,
  }) async {
    try {
      final file = File(p.join((await _userDir(userId)).path, _roomFileName(roomId)));
      if (!await file.exists()) return null;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(map['savedAt'] as String? ?? '');
      if (savedAt == null) return null;
      final messagesRaw = map['messages'] as List<dynamic>? ?? [];
      final messages = messagesRaw
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return CachedRoomMessages(
        messages: messages,
        cursor: map['cursor'] as String?,
        hasMore: map['hasMore'] as bool? ?? true,
        savedAt: savedAt,
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
    try {
      final trimmed = messages.length > _maxMessagesPerRoom
          ? messages.sublist(messages.length - _maxMessagesPerRoom)
          : messages;
      final file = File(p.join((await _userDir(userId)).path, _roomFileName(roomId)));
      await file.writeAsString(
        jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'cursor': cursor,
          'hasMore': hasMore,
          'messages': trimmed.map((m) => m.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> clearUser(String userId) async {
    try {
      _baseDir ??= await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
