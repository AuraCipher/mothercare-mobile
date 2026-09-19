import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/send_intent_store.dart';
import 'package:mobile/features/chat/data/text_send_queue.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/core/storage/app_database.dart';

class FakeTextSocket extends ChatSocketService {
  final sentKeys = <String>[];
  final landedByKey = <String, Map<String, dynamic>>{};
  ChatSendException? failNext;

  Map<String, dynamic> _envelope(String key, String? content, String roomId) {
    return {
      'id': 'msg-$key',
      'roomId': roomId,
      'type': 'text',
      'content': content,
      'mediaFileId': null,
      'mediaFile': null,
      'attachments': [],
      'sender': {'id': 'u', 'name': 'U', 'role': 'student'},
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
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
    final fail = failNext;
    failNext = null;
    if (fail != null) {
      if (fail.uncertain && clientMessageId != null) {
        // Committed server-side, response lost.
        landedByKey[clientMessageId] = _envelope(clientMessageId, content, roomId);
      }
      throw fail;
    }
    final key = clientMessageId ?? 'k';
    sentKeys.add(key);
    final prior = landedByKey[key];
    if (prior != null) return {'message': prior, 'duplicate': true};
    final envelope = _envelope(key, content, roomId);
    landedByKey[key] = envelope;
    return {'message': envelope, 'duplicate': false};
  }
}

class FakeTextApi extends ChatApi {
  FakeTextApi() : super();
  final foundByKey = <String, Map<String, dynamic>>{};

  @override
  Future<ChatMessage?> fetchMessageByClientKey({
    required String token,
    required String roomId,
    required String clientMessageId,
  }) async {
    final raw = foundByKey[clientMessageId];
    if (raw == null) return null;
    return ChatMessage.fromJson(raw);
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  TextSendQueue makeQueue(FakeTextSocket socket, FakeTextApi api, SendIntentStore intents) {
    return TextSendQueue(
      socket: socket,
      getToken: () async => 'tok',
      userId: 'u',
      roomId: 'room-1',
      chatApi: api,
      intents: intents,
    );
  }

  group('M9 offline text queue', () {
    test('online send persists nothing and returns the message', () async {
      final socket = FakeTextSocket();
      final api = FakeTextApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents);

      final msg = await queue.sendText('hello');
      expect(msg.content, 'hello');
      expect(socket.sentKeys, hasLength(1));
      expect(queue.pendings, isEmpty);
      expect(await intents.listRoomIntents('u', 'room-1'), isEmpty);
    });

    test('lost ACK (uncertain) then recover adopts without duplicate', () async {
      final socket = FakeTextSocket();
      final api = FakeTextApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents);

      socket.failNext = ChatSendException('timeout', uncertain: true);
      late final String key;
      try {
        await queue.sendText('uncertain hi');
        fail('expected throw');
      } on ChatSendException catch (e) {
        expect(e.uncertain, isTrue);
        key = queue.pendings.single.clientMessageId;
      }
      // Server landed it; expose via reconcile endpoint.
      api.foundByKey[key] = socket.landedByKey[key]!;
      // Simulate app kill: fresh queue, same store.
      final queue2 = makeQueue(socket, api, intents);
      await queue2.recover();
      expect(socket.sentKeys, isEmpty); // never re-emitted
      expect(queue2.pendings, isEmpty);
      expect(await intents.listRoomIntents('u', 'room-1'), isEmpty);
    });

    test('offline failure then recover resends SAME key (server dedupes)', () async {
      final socket = FakeTextSocket();
      final api = FakeTextApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents);

      socket.failNext = ChatSendException('Not connected. Check your network.');
      String key = '';
      try {
        await queue.sendText('offline hi');
        fail('expected throw');
      } on ChatSendException {
        key = queue.pendings.single.clientMessageId;
      }
      // Restart + connectivity back: recover resends same key.
      final queue2 = makeQueue(socket, api, intents);
      await queue2.recover();
      expect(socket.sentKeys, [key]);
      expect(queue2.pendings, isEmpty);
      // Retry of the same key would be a server-side duplicate replay.
      expect(socket.landedByKey, hasLength(1));
    });

    test('intents past maxRetries stay failed and are never auto-resent', () async {
      final socket = FakeTextSocket();
      final api = FakeTextApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents);
      await intents.saveIntent(
        'u',
        SendIntent(
          clientMessageId: 'stuck-key',
          roomId: 'room-1',
          fileRecordIds: const [],
          caption: 'stuck',
          state: SendIntentState.failed,
          retryCount: 99,
        ),
      );
      await queue.recover();
      expect(socket.sentKeys, isEmpty);
      expect(queue.pendings.single.clientMessageId, 'stuck-key');
      expect(queue.pendings.single.state, SendIntentState.failed);
      await intents.deleteIntent('u', 'room-1', 'stuck-key');
    });
  });
}
