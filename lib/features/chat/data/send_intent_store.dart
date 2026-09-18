import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';

/// Durable send intent for attachment messages (M5 §23-29).
///
/// Reuses the existing `pending_outgoing` table (no new table): rows with
/// `local_id = 'send:<clientMessageId>'` carry the intent JSON. The stable
/// clientMessageId survives process death, so an uncertain send (timeout →
/// kill → restart) reconciles against the SAME key instead of minting a new
/// one (which is what would create duplicates).
///
/// Never stores: auth tokens, file bytes, R2 material.
class SendIntent {
  SendIntent({
    required this.clientMessageId,
    required this.roomId,
    required this.fileRecordIds,
    this.caption,
    this.state = SendIntentState.sending,
    this.retryCount = 0,
    this.error,
    this.uncertain = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String clientMessageId;
  final String roomId;
  final List<String> fileRecordIds;
  final String? caption;
  final SendIntentState state;
  final int retryCount;
  final String? error;
  final bool uncertain;
  final DateTime createdAt;
  final DateTime updatedAt;

  SendIntent copyWith({
    SendIntentState? state,
    int? retryCount,
    String? error,
    bool? uncertain,
  }) =>
      SendIntent(
        clientMessageId: clientMessageId,
        roomId: roomId,
        fileRecordIds: fileRecordIds,
        caption: caption,
        state: state ?? this.state,
        retryCount: retryCount ?? this.retryCount,
        error: error,
        uncertain: uncertain ?? this.uncertain,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'clientMessageId': clientMessageId,
        'roomId': roomId,
        'fileRecordIds': fileRecordIds,
        'caption': caption,
        'state': state.name,
        'retryCount': retryCount,
        'error': error,
        'uncertain': uncertain,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  static SendIntent fromJson(Map<String, dynamic> json) => SendIntent(
        clientMessageId: json['clientMessageId'] as String,
        roomId: json['roomId'] as String,
        fileRecordIds: (json['fileRecordIds'] as List).cast<String>(),
        caption: json['caption'] as String?,
        state: SendIntentState.values.byName(json['state'] as String),
        retryCount: (json['retryCount'] as int?) ?? 0,
        error: json['error'] as String?,
        uncertain: (json['uncertain'] as bool?) ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );
}

enum SendIntentState {
  /// Emit in flight (or never confirmed).
  sending,
  /// Emit timed out after the server may have committed — must reconcile.
  uncertain,
  /// Certain failure — explicit user retry reuses the key.
  failed,
}

class SendIntentStore {
  SendIntentStore({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static String rowId(String clientMessageId) => 'send:$clientMessageId';

  static bool isIntentRow(String localId) => localId.startsWith('send:');

  Future<void> saveIntent(String userId, SendIntent intent) async {
    final db = await _database.database;
    await db.insert(
      'pending_outgoing',
      {
        'user_id': userId,
        'room_id': intent.roomId,
        'local_id': rowId(intent.clientMessageId),
        'sort_key': intent.updatedAt.millisecondsSinceEpoch,
        'payload': jsonEncode(intent.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SendIntent?> loadIntent(String userId, String roomId, String clientMessageId) async {
    final db = await _database.database;
    final rows = await db.query(
      'pending_outgoing',
      where: 'user_id = ? AND room_id = ? AND local_id = ?',
      whereArgs: [userId, roomId, rowId(clientMessageId)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return SendIntent.fromJson(jsonDecode(rows.first['payload'] as String));
    } catch (_) {
      return null;
    }
  }

  /// All intents needing reconciliation for a room (sending/uncertain/failed).
  Future<List<SendIntent>> listRoomIntents(String userId, String roomId) async {
    final db = await _database.database;
    final rows = await db.query(
      'pending_outgoing',
      where: 'user_id = ? AND room_id = ? AND local_id LIKE ?',
      whereArgs: [userId, roomId, 'send:%'],
      orderBy: 'sort_key ASC',
    );
    final out = <SendIntent>[];
    for (final row in rows) {
      try {
        out.add(SendIntent.fromJson(jsonDecode(row['payload'] as String)));
      } catch (_) {}
    }
    return out;
  }

  Future<void> deleteIntent(String userId, String roomId, String clientMessageId) async {
    final db = await _database.database;
    await db.delete(
      'pending_outgoing',
      where: 'user_id = ? AND room_id = ? AND local_id = ?',
      whereArgs: [userId, roomId, rowId(clientMessageId)],
    );
  }
}
