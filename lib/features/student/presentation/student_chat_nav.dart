import 'package:flutter/material.dart';

import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../../chat/presentation/student_system_room_screen.dart';
import '../../student/models/student_bootstrap.dart';
import '../../../core/storage/session_storage.dart';

const studentSystemRecordKinds = {
  'system_attendance',
  'system_payment',
  'system_result',
};

bool isStudentSystemRecordRoom(String kind) => studentSystemRecordKinds.contains(kind);

String? inferStudentSystemRoomKind(String roomName) {
  final name = roomName.toLowerCase();
  if (name.contains('attendance')) return 'system_attendance';
  if (name.contains('payment') || name.contains('fee') || name.contains('receipt')) return 'system_payment';
  if (name.contains('result')) return 'system_result';
  return null;
}

String displaySystemRecordName(String kind) {
  switch (kind) {
    case 'system_attendance':
      return 'Attendance';
    case 'system_payment':
      return 'Fees & Payments';
    case 'system_result':
      return 'Results';
    default:
      return 'School Record';
  }
}

void openStudentChatRoom({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required ChatRoomSummary room,
  required StudentBootstrap bootstrap,
}) {
  if (!context.mounted) return;
  final kind = room.kind;
  if (isStudentSystemRecordRoom(kind)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentSystemRoomScreen(
          session: session,
          socket: socket,
          room: room,
          bootstrap: bootstrap,
        ),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatRoomScreen(
        session: session,
        socket: socket,
        room: room,
        groupLabel: bootstrap.groupLabel,
        academicYearId: bootstrap.academicYearId,
      ),
    ),
  );
}

Future<void> openStudentChatRoomAndWait({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required ChatRoomSummary room,
  required StudentBootstrap bootstrap,
}) async {
  if (!context.mounted) return;
  final kind = room.kind;
  if (isStudentSystemRecordRoom(kind)) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentSystemRoomScreen(
          session: session,
          socket: socket,
          room: room,
          bootstrap: bootstrap,
        ),
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatRoomScreen(
        session: session,
        socket: socket,
        room: room,
        groupLabel: bootstrap.groupLabel,
        academicYearId: bootstrap.academicYearId,
      ),
    ),
  );
}

void openStudentChatRoomFromPush({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required String roomId,
  required String roomName,
  required StudentBootstrap bootstrap,
  // M9: authoritative kind resolved from cached landing data by the caller.
  // Falls back to the name heuristic only when absent (legacy path).
  String? roomKind,
}) {
  final kind = (roomKind != null && roomKind.isNotEmpty) ? roomKind : (inferStudentSystemRoomKind(roomName) ?? '');
  openStudentChatRoom(
    context: context,
    session: session,
    socket: socket,
    bootstrap: bootstrap,
    room: ChatRoomSummary(
      id: roomId,
      kind: kind,
      name: roomName,
      canPost: false,
      unreadCount: 0,
    ),
  );
}
