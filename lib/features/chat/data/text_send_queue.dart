import 'package:flutter/foundation.dart';

import '../../uploads/resumable_upload_engine.dart' show UploadTokenProvider;
import '../../uploads/upload_task.dart' show newIdempotencyKey;
import '../models/chat_models.dart';
import 'chat_api.dart';
import 'chat_socket_service.dart';
import 'send_intent_store.dart';

/// M9: durable offline text-send queue reusing the M4/M5 send-intent
/// machinery (same table, same idempotency keys, same reconcile endpoint).
///
/// Lifecycle: compose → persist intent (sending) → ack-send → delete intent.
/// Offline/kill/timeout → intent survives → [recover] reconciles each key via
/// `by-client-key` (server already has it → adopt, no duplicate) or resends
/// the SAME key (server dedupes). Retries are bounded ([maxRetries]); beyond
/// that the intent stays `failed` for explicit user retry.
class TextPending {
  TextPending({
    required this.clientMessageId,
    required this.text,
    required this.state,
    this.error,
    this.retryCount = 0,
  });

  final String clientMessageId;
  final String text;
  final SendIntentState state;
  final String? error;
  final int retryCount;
}

class TextSendQueue extends ChangeNotifier {
  TextSendQueue({
    required ChatSocketService socket,
    required UploadTokenProvider getToken,
    required String userId,
    required String roomId,
    ChatApi? chatApi,
    SendIntentStore? intents,
    this.maxRetries = 5,
  })  : _socket = socket,
        _getToken = getToken,
        _userId = userId,
        _roomId = roomId,
        _chatApi = chatApi ?? ChatApi(),
        _intents = intents ?? SendIntentStore();

  final ChatSocketService _socket;
  final UploadTokenProvider _getToken;
  final String _userId;
  final String _roomId;
  final ChatApi _chatApi;
  final SendIntentStore _intents;
  final int maxRetries;

  final Map<String, TextPending> _pendings = {};
  bool _sending = false;

  /// In-memory pending/failed view for the composer (persisted source of
  /// truth is the intent store; [recover] rebuilds this after restart).
  List<TextPending> get pendings => _pendings.values.toList();

  /// Send one text message durably. Returns the server message on ack
  /// (fresh or duplicate replay). Throws [ChatSendException] with the
  /// intent left in `uncertain`/`failed` for retry/recover.
  Future<ChatMessage> sendText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) throw ArgumentError('text is empty');
    if (_sending) throw StateError('Send already in progress');
    final key = newIdempotencyKey();
    _sending = true;
    try {
      return await _emit(key: key, text: text, retryCount: 0);
    } finally {
      _sending = false;
    }
  }

  /// Explicit retry of a failed/uncertain text — SAME clientMessageId.
  Future<ChatMessage> retryText(String clientMessageId) async {
    final existing = _pendings[clientMessageId] ??
        await _loadPending(clientMessageId) ??
        (throw StateError('No pending text to retry'));
    if (_sending) throw StateError('Send already in progress');
    _sending = true;
    try {
      return await _emit(
        key: existing.clientMessageId,
        text: existing.text,
        retryCount: existing.retryCount,
      );
    } finally {
      _sending = false;
    }
  }

  /// Reconcile every persisted text intent for this room: adopt landed
  /// messages, resend unlanded ones with the same key (bounded), drop
  /// intents that exceed [maxRetries] into `failed`. Call on room open
  /// and on socket reconnect.
  Future<void> recover() async {
    List<SendIntent> intents;
    try {
      intents = await _intents.listRoomIntents(_userId, _roomId);
    } catch (_) {
      return;
    }
    for (final intent in intents) {
      if (intent.fileRecordIds.isNotEmpty) continue; // attachment tray owns these
      if (intent.state != SendIntentState.sending &&
          intent.state != SendIntentState.uncertain &&
          intent.state != SendIntentState.failed) {
        continue;
      }
      final caption = intent.caption;
      if (caption == null || caption.trim().isEmpty) {
        try {
          await _intents.deleteIntent(_userId, _roomId, intent.clientMessageId);
        } catch (_) {}
        continue;
      }
      if (intent.retryCount >= maxRetries && intent.state == SendIntentState.failed) {
        _pendings[intent.clientMessageId] = TextPending(
          clientMessageId: intent.clientMessageId,
          text: caption,
          state: SendIntentState.failed,
          error: intent.error ?? 'Send failed after $maxRetries attempts.',
          retryCount: intent.retryCount,
        );
        continue;
      }
      final reconciled = await _reconcileKey(intent.clientMessageId);
      if (reconciled != null) continue;
      if (_sending) {
        _pendings[intent.clientMessageId] = TextPending(
          clientMessageId: intent.clientMessageId,
          text: caption,
          state: intent.state,
          error: intent.error,
          retryCount: intent.retryCount,
        );
        continue;
      }
      _sending = true;
      try {
        await _emit(
          key: intent.clientMessageId,
          text: caption,
          retryCount: intent.retryCount,
        );
      } catch (_) {
        // Intent persists with its new state; UI reads pendings below.
      } finally {
        _sending = false;
      }
    }
    notifyListeners();
  }

  Future<ChatMessage> _emit({
    required String key,
    required String text,
    required int retryCount,
  }) async {
    await _persistIntent(SendIntentState.sending, key, text, retryCount, null, false);
    _setPending(key, text, SendIntentState.sending, null, retryCount);
    try {
      final res = await _socket.sendMessageWithAck(
        roomId: _roomId,
        content: text,
        type: 'text',
        clientMessageId: key,
      );
      final message = ChatMessage.fromSocket(res['message'] as Map<String, dynamic>);
      _pendings.remove(key);
      try {
        await _intents.deleteIntent(_userId, _roomId, key);
      } catch (_) {}
      notifyListeners();
      return message;
    } on ChatSendException catch (e) {
      final state = e.uncertain ? SendIntentState.uncertain : SendIntentState.failed;
      await _persistIntent(state, key, text, retryCount + 1, e.message, e.uncertain);
      _setPending(key, text, state, e.message, retryCount + 1);
      rethrow;
    }
  }

  /// Adopt-only reconcile: returns the message if the server already has
  /// this key (deletes the intent), else null.
  Future<ChatMessage?> _reconcileKey(String key) async {
    try {
      final token = await _getToken();
      if (token == null) return null;
      final found = await _chatApi.fetchMessageByClientKey(
        token: token,
        roomId: _roomId,
        clientMessageId: key,
      );
      if (found == null) return null;
      _pendings.remove(key);
      try {
        await _intents.deleteIntent(_userId, _roomId, key);
      } catch (_) {}
      notifyListeners();
      return found;
    } catch (_) {
      return null;
    }
  }

  Future<TextPending?> _loadPending(String clientMessageId) async {
    try {
      final intent = await _intents.loadIntent(_userId, _roomId, clientMessageId);
      if (intent == null || intent.fileRecordIds.isNotEmpty) return null;
      final caption = intent.caption;
      if (caption == null) return null;
      final pending = TextPending(
        clientMessageId: intent.clientMessageId,
        text: caption,
        state: intent.state,
        error: intent.error,
        retryCount: intent.retryCount,
      );
      _pendings[intent.clientMessageId] = pending;
      return pending;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistIntent(
    SendIntentState state,
    String key,
    String text,
    int retryCount,
    String? error,
    bool uncertain,
  ) async {
    try {
      final existing = await _intents.loadIntent(_userId, _roomId, key);
      await _intents.saveIntent(
        _userId,
        SendIntent(
          clientMessageId: key,
          roomId: _roomId,
          fileRecordIds: const [],
          caption: text,
          state: state,
          retryCount: retryCount,
          error: error,
          uncertain: uncertain,
          createdAt: existing?.createdAt,
        ),
      );
    } catch (_) {}
  }

  void _setPending(String key, String text, SendIntentState state, String? error, int retryCount) {
    _pendings[key] = TextPending(
      clientMessageId: key,
      text: text,
      state: state,
      error: error,
      retryCount: retryCount,
    );
    notifyListeners();
  }
}
