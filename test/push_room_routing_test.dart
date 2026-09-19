import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/push/push_room_resolve.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/student/presentation/student_chat_nav.dart';
import 'package:mobile/features/teacher/presentation/teacher_chat_nav.dart';

ChatRoomSummary room(String id, String kind, [String name = 'R']) =>
    ChatRoomSummary(id: id, kind: kind, name: name, canPost: false, unreadCount: 0);

void main() {
  group('M9 push-tap room resolution (stable identifiers first)', () {
    final landing = ChatLandingData(
      sections: [
        ChatLandingSection(
          key: 'system',
          title: 'School Records',
          rooms: [room('r-att', 'system_attendance', 'My Attendance')],
        ),
        const ChatLandingSection(key: 'msgs', title: 'Messages'),
      ],
      rooms: [room('r-dm', 'direct_message', 'Chat with Ali')],
    );

    test('finds system feed in sections by roomId', () {
      expect(findCachedPushRoom(landing, 'r-att')?.kind, 'system_attendance');
    });

    test('finds DM in top-level rooms by roomId', () {
      expect(findCachedPushRoom(landing, 'r-dm')?.kind, 'direct_message');
    });

    test('unknown roomId returns null (caller falls back)', () {
      expect(findCachedPushRoom(landing, 'nope'), isNull);
    });

    test('authoritative kind beats misleading display names', () {
      // A system room renamed to something unguessable still routes by kind.
      final renamed = ChatLandingData(sections: const [], rooms: [
        room('r-x', 'system_payment', 'Misc Updates'),
      ]);
      expect(findCachedPushRoom(renamed, 'r-x')?.kind, 'system_payment');
      // The legacy name heuristic would have missed it:
      expect(inferStudentSystemRoomKind('Misc Updates'), isNull);
    });

    test('teacher system kinds route to fixed feeds, others to generic', () {
      expect(isTeacherSystemRecordRoom('system_teacher_attendance'), isTrue);
      expect(isTeacherSystemRecordRoom('system_teacher_payroll'), isTrue);
      expect(isTeacherSystemRecordRoom('direct_message'), isFalse);
      expect(isTeacherSystemRecordRoom(''), isFalse);
    });

    test('student system kinds recognized', () {
      expect(isStudentSystemRecordRoom('system_attendance'), isTrue);
      expect(isStudentSystemRecordRoom('system_payment'), isTrue);
      expect(isStudentSystemRecordRoom('system_result'), isTrue);
      expect(isStudentSystemRecordRoom('group_chat'), isFalse);
    });
  });
}
