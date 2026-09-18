import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/chat_socket_service.dart';
import 'package:mobile/features/chat/data/chat_upload_pool.dart';

void main() {
  group('socket send payload (M4)', () {
    test('multi-attachment payload carries ids + client key, mirrors first', () {
      final payload = ChatSocketService.buildSendPayload(
        roomId: 'room-1',
        content: 'trip',
        type: 'image',
        mediaFileId: 'f1',
        mediaFileIds: const ['f1', 'f2', 'f3'],
        clientMessageId: 'key-1',
      );
      expect(payload['roomId'], 'room-1');
      expect(payload['mediaFileIds'], ['f1', 'f2', 'f3']);
      expect(payload['mediaFileId'], 'f1');
      expect(payload['clientMessageId'], 'key-1');
      expect(payload['content'], 'trip');
    });

    test('legacy text payload unchanged in shape', () {
      final payload = ChatSocketService.buildSendPayload(roomId: 'room-1', content: 'hi');
      expect(payload['type'], 'text');
      expect(payload.containsKey('mediaFileIds'), isFalse);
      expect(payload.containsKey('clientMessageId'), isFalse);
    });

    test('ChatSendException carries uncertainty for timeout-retry decisions', () {
      final certain = ChatSendException('Nope.');
      expect(certain.uncertain, isFalse);
      final uncertain = ChatSendException('Maybe.', uncertain: true);
      expect(uncertain.uncertain, isTrue);
    });
  });

  group('ChatUploadPool isolation', () {
    test('schedulers are per-user; releaseAll drops them', () async {
      Future<String?> token() async => 'tok';
      final a1 = ChatUploadPool.acquire(userId: 'user-a', getToken: token);
      final a2 = ChatUploadPool.acquire(userId: 'user-a', getToken: token);
      final b = ChatUploadPool.acquire(userId: 'user-b', getToken: token);
      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b), isFalse);
      await ChatUploadPool.releaseAll();
      expect(ChatUploadPool.isEmpty, isTrue);
      final a3 = ChatUploadPool.acquire(userId: 'user-a', getToken: token);
      expect(identical(a1, a3), isFalse);
      await ChatUploadPool.releaseAll();
    });
  });
}
