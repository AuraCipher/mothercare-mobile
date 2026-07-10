import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../config/app_config.dart';
import '../models/chat_models.dart';

class ChatSocketService {
  io.Socket? _socket;
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<ChatMessage> get onMessage => _messageController.stream;
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
  }) {
    _socket?.emit('chat:message:send', {
      'roomId': roomId,
      'type': type,
      if (content != null && content.isNotEmpty) 'content': content,
      'mediaFileId': ?mediaFileId,
    });
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
    _errorController.close();
  }
}
