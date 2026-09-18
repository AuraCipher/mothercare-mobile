import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/chat_models.dart';

Map<String, dynamic> _media(String id) => {
      'id': id,
      'mimeType': 'image/jpeg',
      'publicUrl': '/api/uploads/$id',
      'purpose': 'chat',
    };

void main() {
  group('multi-attachment parsing', () {
    test('attachments list parsed in order; mediaFile preserved', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'roomId': 'r1',
        'type': 'image',
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mediaFile': _media('f1'),
        'attachments': [_media('f1'), _media('f2'), _media('f3')],
      });
      expect(msg.attachments.map((a) => a.id).toList(), ['f1', 'f2', 'f3']);
      expect(msg.displayAttachments.map((a) => a.id).toList(), ['f1', 'f2', 'f3']);
      expect(msg.mediaFile?.id, 'f1');
    });

    test('legacy message without attachments falls back to mediaFile', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'roomId': 'r1',
        'type': 'image',
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mediaFile': _media('f1'),
      });
      expect(msg.attachments, isEmpty);
      expect(msg.displayAttachments.map((a) => a.id).toList(), ['f1']);
      expect(msg.hasAttachments, isTrue);
    });

    test('text message has no attachments', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'roomId': 'r1',
        'type': 'text',
        'content': 'hi',
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(msg.displayAttachments, isEmpty);
      expect(msg.hasAttachments, isFalse);
    });

    test('fromSocket parses attachments; empty entries filtered', () {
      final msg = ChatMessage.fromSocket({
        'id': 'm1',
        'roomId': 'r1',
        'type': 'document',
        'sender': {'id': 'u', 'name': 'U', 'role': 'teacher'},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'attachments': [_media('f1'), {'id': '', 'mimeType': '', 'url': ''}],
      });
      expect(msg.attachments.map((a) => a.id).toList(), ['f1']);
    });

    test('toJson round-trips attachments; legacy shape omits the key', () {
      final withAtt = ChatMessage(
        id: 'm1', roomId: 'r1', type: 'image',
        sender: const ChatMessageSender(id: 'u', name: 'U', role: 'teacher'),
        createdAt: DateTime.now(),
        mediaFile: ChatMessageMedia.fromJson(_media('f1')),
        attachments: [ChatMessageMedia.fromJson(_media('f1')), ChatMessageMedia.fromJson(_media('f2'))],
      );
      final back = ChatMessage.fromJson(withAtt.toJson());
      expect(back.attachments.map((a) => a.id).toList(), ['f1', 'f2']);

      final legacy = ChatMessage(
        id: 'm2', roomId: 'r1', type: 'text', content: 'hi',
        sender: const ChatMessageSender(id: 'u', name: 'U', role: 'teacher'),
        createdAt: DateTime.now(),
      );
      expect((legacy.toJson())['attachments'], isNull);
      expect(ChatMessage.fromJson(legacy.toJson()).displayAttachments, isEmpty);
    });

    test('isImageMessage/isDocumentMessage span attachments', () {
      final msg = ChatMessage(
        id: 'm1', roomId: 'r1', type: 'document',
        sender: const ChatMessageSender(id: 'u', name: 'U', role: 'teacher'),
        createdAt: DateTime.now(),
        attachments: [ChatMessageMedia.fromJson(_media('f1'))],
      );
      expect(msg.isImageMessage, isTrue);
    });
  });
}
