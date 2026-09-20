import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/core/api/authenticated_client.dart';
import 'package:mobile/core/storage/app_database.dart';
import 'package:mobile/features/chat/data/chat_api.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/send_intent_store.dart';
import 'package:mobile/features/chat/data/text_send_queue.dart';

/// Opt-in LIVE E2E (M9 §6): real Flutter queue plus real Socket.IO plus real
/// backend plus real PostgreSQL. Nothing mocked except the process boundary.
///
/// Runs ONLY when all env vars are present (example values shown with
/// placeholder tokens, not HTML):
///   M9_LIVE_BACKEND=1
///   M9_API_URL=http://127.0.0.1:5003
///   M9_TOKEN set to a jwt, M9_ROOM_ID set to a room,
///   M9_USER_ID set to a user, M9_AY_ID set to an ay.
///
/// Backend setup (m6_test): a group_chat room + branch_admin membership so
/// the sender can post; membership heals on first access.
void main() {
  final enabled = Platform.environment['M9_LIVE_BACKEND'] == '1';
  final baseUrl = Platform.environment['M9_API_URL'] ?? '';
  final token = Platform.environment['M9_TOKEN'] ?? '';
  final roomId = Platform.environment['M9_ROOM_ID'] ?? '';
  final userId = Platform.environment['M9_USER_ID'] ?? '';
  final ayId = Platform.environment['M9_AY_ID'] ?? '';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  TextSendQueue makeQueue(ChatSocketService socket, ChatApi api) {
    return TextSendQueue(
      socket: socket,
      getToken: () async => token,
      userId: userId,
      roomId: roomId,
      chatApi: api,
      intents: SendIntentStore(),
    );
  }

  Future<ChatSocketService> connectSocket() async {
    final socket = ChatSocketService();
    socket.connect(token: token, academicYearId: ayId, baseUrl: baseUrl);
    // Wait for connect (join is emitted on connect).
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!socket.isConnected) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('socket did not connect to $baseUrl');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    socket.joinRoom(roomId);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return socket;
  }

  test('A: online text send lands exactly once (Flutter→socket→DB→history)', () async {
    if (!enabled || token.isEmpty || baseUrl.isEmpty) {
      markTestSkipped('Set M9_LIVE_BACKEND=1 M9_API_URL=... M9_TOKEN=... to run.');
      return;
    }
    final api = ChatApi(client: AuthenticatedClient(baseUrl: baseUrl));
    final socket = await connectSocket();
    final queue = makeQueue(socket, api);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final text = 'm9-live-a-$stamp';

    final msg = await queue.sendText(text);
    expect(msg.id, isNotEmpty);
    expect(msg.content, text);

    final history = await api.fetchMessages(token: token, roomId: roomId, limit: 40);
    expect(history.where((m) => m.content == text), hasLength(1));
    socket.dispose();
    queue.dispose();
  });

  test('D: same-key double emit converges server-side (duplicate:true, one row)', () async {
    if (!enabled || token.isEmpty || baseUrl.isEmpty) {
      markTestSkipped('Set M9_LIVE_BACKEND=1 M9_API_URL=... M9_TOKEN=... to run.');
      return;
    }
    final api = ChatApi(client: AuthenticatedClient(baseUrl: baseUrl));
    final socket = await connectSocket();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    const keyPrefix = 'm9-live-dup';
    final key = '$keyPrefix-$stamp';
    final text = 'm9-live-d-$stamp';

    final first = await socket.sendMessageWithAck(
      roomId: roomId, content: text, type: 'text', clientMessageId: key,
    );
    expect((first['message'] as Map)['content'], text);
    final second = await socket.sendMessageWithAck(
      roomId: roomId, content: text, type: 'text', clientMessageId: key,
    );
    expect(second['duplicate'], isTrue);

    final found = await api.fetchMessageByClientKey(
      token: token, roomId: roomId, clientMessageId: key,
    );
    expect(found, isNotNull);
    socket.dispose();
  });

  test('E: offline send persists, reconnect recover lands exactly once', () async {
    if (!enabled || token.isEmpty || baseUrl.isEmpty) {
      markTestSkipped('Set M9_LIVE_BACKEND=1 M9_API_URL=... M9_TOKEN=... to run.');
      return;
    }
    final api = ChatApi(client: AuthenticatedClient(baseUrl: baseUrl));
    final socket = await connectSocket();
    final intents = SendIntentStore();
    final queue = TextSendQueue(
      socket: socket,
      getToken: () async => token,
      userId: userId,
      roomId: roomId,
      chatApi: api,
      intents: intents,
    );
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final text = 'm9-live-e-$stamp';

    // Go offline: dispose the socket so emits fail deterministically.
    socket.dispose();
    try {
      await queue.sendText(text);
      fail('expected offline failure');
    } on ChatSendException {
      // Intent persisted as failed.
    }
    expect(queue.pendings, hasLength(1));

    // Reconnect with a fresh socket + fresh queue (simulates restart).
    final socket2 = await connectSocket();
    final queue2 = TextSendQueue(
      socket: socket2,
      getToken: () async => token,
      userId: userId,
      roomId: roomId,
      chatApi: api,
      intents: intents,
    );
    await queue2.recover();
    expect(queue2.pendings, isEmpty);

    final history = await api.fetchMessages(token: token, roomId: roomId, limit: 40);
    expect(history.where((m) => m.content == text), hasLength(1));
    socket2.dispose();
    queue.dispose();
    queue2.dispose();
  });
}
