import 'package:mobile/core/storage/chat_message_cache_store.dart';
import 'package:mobile/features/chat/models/chat_models.dart';

import 'mock_api_router.dart';

ChatMessage e2eDemoMessage({required String id, required String content}) {
  return ChatMessage(
    id: id,
    roomId: E2eIds.schoolRoomId,
    type: 'text',
    content: content,
    sender: const ChatMessageSender(id: 'user-teacher-1', name: 'Ms. Nadia', role: 'teacher'),
    createdAt: DateTime.parse('2026-07-10T10:00:00.000Z'),
  );
}

Future<void> seedSchoolRoomCache({String userId = 'user-student-1'}) async {
  await ChatMessageCacheStore.instance.saveRoom(
    userId: userId,
    roomId: E2eIds.schoolRoomId,
    messages: [
      e2eDemoMessage(id: 'msg-1', content: 'Welcome to the demo channel.'),
      e2eDemoMessage(id: 'msg-2', content: 'Please check the latest notice.'),
    ],
  );
}
