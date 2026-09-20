import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/send_intent_store.dart';
import 'package:mobile/features/chat/data/text_send_queue.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/core/storage/app_database.dart';

/// M10 §2 soak: scripted socket with controllable failure modes.
class SoakSocket extends ChatSocketService {
  final landedByKey = <String, Map<String, dynamic>>{};
  final sentKeys = <String>[];
  int forcedFailures = 0;
  bool uncertainLoss = false;

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
    final key = clientMessageId ?? 'k';
    if (forcedFailures > 0) {
      forcedFailures -= 1;
      if (uncertainLoss) {
        landedByKey[key] = _envelope(key, content, roomId);
        throw ChatSendException('timeout', uncertain: true);
      }
      throw ChatSendException('Not connected.');
    }
    sentKeys.add(key);
    final prior = landedByKey[key];
    if (prior != null) return {'message': prior, 'duplicate': true};
    final envelope = _envelope(key, content, roomId);
    landedByKey[key] = envelope;
    return {'message': envelope, 'duplicate': false};
  }
}

class SoakApi extends ChatApi {
  SoakApi() : super();
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

  TextSendQueue makeQueue(SoakSocket socket, SoakApi api, SendIntentStore intents, String room) {
    return TextSendQueue(
      socket: socket,
      getToken: () async => 'tok',
      userId: 'u',
      roomId: room,
      chatApi: api,
      intents: intents,
    );
  }

  group('M10 text soak', () {
    test('rapid 10/25/50: every message lands exactly once, no pendings', () async {
      for (final n in [10, 25, 50]) {
        final socket = SoakSocket();
        final api = SoakApi();
        final intents = SendIntentStore();
        final queue = makeQueue(socket, api, intents, 'room-$n');
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < n; i++) {
          // ignore: use_build_context_synchronously (test)
          await queue.sendText('soak-$n-$i');
        }
        stopwatch.stop();
        expect(socket.landedByKey, hasLength(n));
        expect(socket.sentKeys, hasLength(n));
        expect(socket.sentKeys.toSet(), hasLength(n)); // unique keys
        expect(queue.pendings, isEmpty);
        expect(await intents.listRoomIntents('u', 'room-$n'), isEmpty);
        // ignore: avoid_print
        print('rapid-$n: ${stopwatch.elapsedMilliseconds}ms, landed=${socket.landedByKey.length}');
      }
    });

    test('alternating rooms stay isolated', () async {
      final socket = SoakSocket();
      final api = SoakApi();
      final intents = SendIntentStore();
      final qa = makeQueue(socket, api, intents, 'room-A');
      final qb = makeQueue(socket, api, intents, 'room-B');
      for (var i = 0; i < 10; i++) {
        await (i.isEven ? qa : qb).sendText('alt-$i');
      }
      final aIntents = await intents.listRoomIntents('u', 'room-A');
      final bIntents = await intents.listRoomIntents('u', 'room-B');
      expect(aIntents, isEmpty);
      expect(bIntents, isEmpty);
      // Server keyed every emit once; rooms never crossed (envelopes carry room).
      for (final e in socket.landedByKey.values) {
        expect((e['roomId'] as String).startsWith('room-'), isTrue);
      }
      final aCount = socket.landedByKey.values.where((e) => e['roomId'] == 'room-A').length;
      final bCount = socket.landedByKey.values.where((e) => e['roomId'] == 'room-B').length;
      expect(aCount, 5);
      expect(bCount, 5);
    });

    test('offline batch of 10 + kill + restart + reconnect: all land once', () async {
      final socket = SoakSocket();
      final api = SoakApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents, 'room-off');
      socket.forcedFailures = 100; // offline
      final keys = <String>[];
      for (var i = 0; i < 10; i++) {
        try {
          await queue.sendText('offline-$i');
          fail('expected offline failure');
        } on ChatSendException {
          keys.add(queue.pendings.last.clientMessageId);
        }
      }
      expect(keys.toSet(), hasLength(10));
      expect(socket.landedByKey, isEmpty);
      // Kill: drop the queue; restart with a fresh instance on the same store.
      final queue2 = makeQueue(socket, api, intents, 'room-off');
      socket.forcedFailures = 0; // connectivity back
      final sw = Stopwatch()..start();
      await queue2.recover();
      sw.stop();
      expect(queue2.pendings, isEmpty);
      expect(socket.landedByKey, hasLength(10));
      final sentSet = socket.sentKeys.toSet();
      expect(sentSet, hasLength(10));
      expect(sentSet, keys.toSet()); // SAME keys reused, no new identities
      // ignore: avoid_print
      print('offline-recover-10: ${sw.elapsedMilliseconds}ms');
    });

    test('lost-ACK storm: 10 uncertain sends converge, zero duplicates', () async {
      final socket = SoakSocket();
      final api = SoakApi();
      final intents = SendIntentStore();
      final queue = makeQueue(socket, api, intents, 'room-ack');
      socket.forcedFailures = 100;
      socket.uncertainLoss = true;
      final keys = <String>[];
      for (var i = 0; i < 10; i++) {
        try {
          await queue.sendText('ack-$i');
          fail('expected uncertain failure');
        } on ChatSendException catch (e) {
          expect(e.uncertain, isTrue);
          keys.add(queue.pendings.last.clientMessageId);
        }
      }
      expect(socket.landedByKey, hasLength(10)); // all landed server-side
      // Expose landed rows to the reconcile endpoint, then recover.
      api.foundByKey.addAll(socket.landedByKey);
      socket.forcedFailures = 0;
      socket.uncertainLoss = false;
      final queue2 = makeQueue(socket, api, intents, 'room-ack');
      await queue2.recover();
      expect(socket.sentKeys, isEmpty); // adopted, never re-emitted
      expect(socket.landedByKey, hasLength(10)); // still exactly 10
      expect(queue2.pendings, isEmpty);
    });

    test('bounded retries: persistent failure parks as failed, retryable', () async {
      final socket = SoakSocket();
      final api = SoakApi();
      final intents = SendIntentStore();
      final queue = TextSendQueue(
        socket: socket,
        getToken: () async => 'tok',
        userId: 'u',
        roomId: 'room-retry',
        chatApi: api,
        intents: intents,
        maxRetries: 2,
      );
      socket.forcedFailures = 100; // offline forever
      try {
        await queue.sendText('doomed');
        fail('expected failure');
      } on ChatSendException {
        // failed intent persists
      }
      final key = queue.pendings.single.clientMessageId;
      // Recover attempts bounded resends then parks failed (no infinite loop).
      final queue2 = TextSendQueue(
        socket: socket,
        getToken: () async => 'tok',
        userId: 'u',
        roomId: 'room-retry',
        chatApi: api,
        intents: intents,
        maxRetries: 2,
      );
      await queue2.recover();
      final pending = queue2.pendings.single;
      expect(pending.clientMessageId, key); // SAME key
      expect(pending.state.name, 'failed');
      expect(socket.landedByKey, isEmpty); // nothing landed
      // Explicit retry still possible later (does not throw StateError).
      socket.forcedFailures = 0;
      final msg = await queue2.retryText(key);
      expect(msg.content, 'doomed');
      expect(queue2.pendings, isEmpty);
    });
  });
}
