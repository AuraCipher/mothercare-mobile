import 'package:flutter/material.dart';

import '../../chat/data/chat_socket_service.dart';
import '../../chat/models/chat_models.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../../chat/presentation/teacher_system_room_screen.dart';
import '../models/teacher_bootstrap.dart';
import '../../../core/storage/session_storage.dart';

const teacherSystemRecordKinds = {
  'system_teacher_attendance',
  'system_teacher_payroll',
};

bool isTeacherSystemRecordRoom(String kind) => teacherSystemRecordKinds.contains(kind);

String displayTeacherSystemRecordName(String kind) {
  switch (kind) {
    case 'system_teacher_attendance':
      return 'My Attendance';
    case 'system_teacher_payroll':
      return 'My Payroll';
    default:
      return 'My Record';
  }
}

void openTeacherChatRoom({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required ChatRoomSummary room,
  required TeacherBootstrap bootstrap,
}) {
  if (!context.mounted) return;
  if (isTeacherSystemRecordRoom(room.kind)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherSystemRoomScreen(
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
        academicYearId: bootstrap.academicYearId,
        branchId: bootstrap.branchId,
      ),
    ),
  );
}

Future<void> openTeacherChatRoomAndWait({
  required BuildContext context,
  required StoredSession session,
  required ChatSocketService socket,
  required ChatRoomSummary room,
  required TeacherBootstrap bootstrap,
}) async {
  if (!context.mounted) return;
  if (isTeacherSystemRecordRoom(room.kind)) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherSystemRoomScreen(
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
        academicYearId: bootstrap.academicYearId,
        branchId: bootstrap.branchId,
      ),
    ),
  );
}
