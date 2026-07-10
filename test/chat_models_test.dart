import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/student/models/student_bootstrap.dart';

void main() {
  test('ChatLandingData parses sections and rooms', () {
    final data = ChatLandingData.fromJson({
      'sections': [
        {
          'key': 'school',
          'title': 'School Announcement',
          'rooms': [
            {
              'id': 'r1',
              'kind': 'school_announcement',
              'name': 'School Announcement',
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
          'name': 'School Announcement',
          'description': null,
          'canPost': false,
          'unreadCount': 2,
          'lastMessageAt': '2026-07-09T10:00:00.000Z',
        },
      ],
    });

    expect(data.sections.length, 1);
    expect(data.rooms.length, 1);
  });

  test('class display name from bootstrap groupLabel', () {
    expect(classDisplayName('Playgroup'), 'Playgroup');
    expect(classDisplayName('Class 8 — CS'), 'Class 8 — CS');
    expect(classDisplayName(null), 'My Class');
  });

  test('class announcement room label inside community screen', () {
    const classRoom = ChatRoomSummary(
      id: 'r2',
      kind: 'class_announcement',
      name: 'Class 8 · CS Announcements',
      canPost: false,
      unreadCount: 0,
    );

    expect(displayRoomName(classRoom), 'Class Announcement');
  });

  test('splits class section into announcement and groups', () {
    final section = ChatLandingSection.fromJson({
      'key': 'class',
      'title': 'Class Community',
      'rooms': [
        {'id': 'a', 'kind': 'class_announcement', 'name': 'X', 'unreadCount': 1, 'canPost': false},
        {'id': 'g', 'kind': 'group_chat', 'name': 'Mathematics', 'unreadCount': 2, 'canPost': true},
      ],
    });

    expect(classAnnouncementRooms(section).length, 1);
    expect(classGroupRooms(section).length, 1);
    expect(classCommunityUnread(section), 3);
  });

  test('normalizeChatLabel renames legacy Whole School', () {
    expect(normalizeChatLabel('Whole School'), 'School Announcement');
    expect(normalizeChatLabel('Mathematics'), 'Mathematics');
  });

  test('StudentBootstrap parses branch and user from API', () {
    final bootstrap = StudentBootstrap.fromJson({
      'academicYear': {'id': 'ay1', 'label': '2025-2026'},
      'branch': {'name': 'Mother Care Sohan', 'code': 'MCS-SOH'},
      'student': {'name': 'Ahmed Ali', 'groupLabel': 'Playgroup', 'rollNumber': 'PG-01'},
      'user': {'name': 'Ahmed Ali'},
    });

    expect(bootstrap.branchName, 'Mother Care Sohan');
    expect(bootstrap.userName, 'Ahmed Ali');
    expect(bootstrap.groupLabel, 'Playgroup');
    expect(bootstrap.academicYearLabel, '2025-2026');
  });
}
