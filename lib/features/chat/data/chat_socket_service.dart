import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';
import '../models/chat_models.dart';

class ChatSocketService {
  io.Socket? _socket;
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _deletedController = StreamController<String>.broadcast();
  final _updatedController = StreamController<ChatMessage>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<ChatMessage> get onMessage => _messageController.stream;
  Stream<String> get onMessageDeleted => _deletedController.stream;
  Stream<ChatMessage> get onMessageUpdated => _updatedController.stream;
  Stream<String> get onError => _errorController.stream;
  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String token,
    required String academicYearId,
    String? baseUrl,
  }) {
    disconnect();

    final url = baseUrl ?? AppConfig.apiBaseUrl;
    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _socket!.emit('chat:join', {'academicYearId': academicYearId});
      })
      ..on('chat:message:new', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _messageController.add(ChatMessage.fromSocket(map));
        }
      })
      ..on('chat:message:deleted', (data) {
        if (data is Map && data['id'] != null) {
          _deletedController.add(data['id'].toString());
        }
      })
      ..on('chat:message:updated', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _updatedController.add(ChatMessage.fromSocket(map));
        }
      })
      ..on('chat:error', (data) {
        if (data is Map && data['message'] != null) {
          _errorController.add(data['message'].toString());
        }
      })
      ..onConnectError((err) {
        _errorController.add('Connection error: $err');
      });
  }

  void joinRoom(String roomId) {
    _socket?.emit('chat:room:join', {'roomId': roomId});
  }

  void sendMessage({
    required String roomId,
    String? content,
    String type = 'text',
    String? mediaFileId,
    List<String>? mediaFileIds,
    String? clientMessageId,
  }) {
    _socket?.emit('chat:message:send', {
      'roomId': roomId,
      'type': type,
      if (content != null && content.isNotEmpty) 'content': content,
      'mediaFileId': ?mediaFileId,
      'mediaFileIds': ?mediaFileIds,
      'clientMessageId': ?clientMessageId,
    });
  }
  /// Testable payload builder (single place both send paths draw from).
  static Map<String, dynamic> buildSendPayload({
    required String roomId,
    String? content,
    String type = 'text',
    String? title,
    String? mediaFileId,
    List<String>? mediaFileIds,
    String? clientMessageId,
  }) {
    return {
      'roomId': roomId,
      'type': type,
      if (content != null && content.isNotEmpty) 'content': content,
      if (title != null && title.isNotEmpty) 'title': title,
      'mediaFileId': ?mediaFileId,
      'mediaFileIds': ?mediaFileIds,
      'clientMessageId': ?clientMessageId,
    };
  }

  /// M4: acknowledged send. Resolves with the server envelope on `{ok:true}`
  /// (including `duplicate:true` replays) or throws [ChatSendException] on
  /// `{ok:false}` / timeout. Old fire-and-forget [sendMessage] is preserved
  /// for callers that correlate via broadcast echo instead.
  Future<Map<String, dynamic>> sendMessageWithAck({
    required String roomId,
    String? content,
    String type = 'text',
    String? mediaFileId,
    List<String>? mediaFileIds,
    String? title,
    String? clientMessageId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw ChatSendException('Not connected. Check your network.');
    }
    final payload = buildSendPayload(
      roomId: roomId,
      content: content,
      type: type,
      title: title,
      mediaFileId: mediaFileId,
      mediaFileIds: mediaFileIds,
      clientMessageId: clientMessageId,
    );
    try {
      // emitWithAckAsync resolves with the server's ack payload
      // ({ok, message?, duplicate?, error?}); see chat.socket.ts.
      final res = await socket.emitWithAckAsync('chat:message:send', [payload]).timeout(timeout);
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] == true) {
        final message = map['message'];
        return {
          'message': message is Map ? Map<String, dynamic>.from(message) : <String, dynamic>{},
          'duplicate': map['duplicate'] == true,
        };
      }
      throw ChatSendException((map['error'] ?? 'Send failed').toString());
    } on TimeoutException {
      // Uncertain outcome (server may have committed): the caller MUST NOT
      // retry blindly — it re-sends with the SAME clientMessageId, and the
      // server dedupes. Mark the failure so the UI offers explicit retry.
      throw ChatSendException('Send timed out. The message may already exist — retry to reconcile.',
          uncertain: true);
    }
  }

  void markRead({required String roomId, String? messageId}) {
    _socket?.emit('chat:message:read', {
      'roomId': roomId,
      'messageId': ?messageId,
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _deletedController.close();
    _updatedController.close();
    _errorController.close();
  }
}

/// Send failure. [uncertain] means the server may already have created the
/// message (timeout after emit) — retry ONLY with the same clientMessageId.
class ChatSendException implements Exception {
  ChatSendException(this.message, {this.uncertain = false});

  final String message;
  final bool uncertain;

  @override
  String toString() => message;
}
