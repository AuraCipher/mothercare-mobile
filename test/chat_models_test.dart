import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/chat_models.dart';

void main() {
  test('ChatLandingData parses sections and rooms', () {
    final data = ChatLandingData.fromJson({
      'sections': [
        {
          'key': 'school',
          'title': 'Whole School',
          'rooms': [
            {
              'id': 'r1',
              'kind': 'school_announcement',
              'name': 'Whole School',
              'unreadCount': 2,
              'lastMessageAt': '2026-07-09T10:00:00.000Z',
              'canPost': false,
            },
          ],
        },
      ],
      'rooms': [
        {
          'id': 'r1',
          'kind': 'school_announcement',
          'name': 'Whole School',
          'description': null,
          'canPost': false,
          'unreadCount': 2,
          'lastMessageAt': '2026-07-09T10:00:00.000Z',
        },
      ],
    });

    expect(data.sections.length, 1);
    expect(data.rooms.length, 1);
    expect(data.roomById('r1')?.name, 'Whole School');
    expect(iconForRoomKind('group_chat'), '💬');
  });

  test('displayRoomName renames school announcement', () {
    const room = ChatRoomSummary(
      id: 'r1',
      kind: 'school_announcement',
      name: 'Whole School',
      canPost: false,
      unreadCount: 0,
    );
    expect(displayRoomName(room), 'Announcement');
  });
}
