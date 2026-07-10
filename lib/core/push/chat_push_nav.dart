import 'package:flutter/material.dart';

import '../../features/chat/models/chat_models.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../storage/session_storage.dart';
import '../../features/chat/data/chat_socket_service.dart';

void openChatRoomFromPush({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required String roomId,
  required String roomName,
  String? academicYearId,
  String? branchId,
  String? groupLabel,
}) {
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatRoomScreen(
        session: session,
        socket: socket,
        room: ChatRoomSummary(
          id: roomId,
          kind: '',
          name: roomName,
          canPost: false,
          unreadCount: 0,
        ),
        groupLabel: groupLabel,
        academicYearId: academicYearId,
        branchId: branchId,
      ),
    ),
  );
}
