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

  test('staff landing groups school announcement section', () {
    final rooms = [
      const ChatRoomSummary(
        id: 'r1',
        kind: 'school_announcement',
        name: 'School Announcement',
        canPost: false,
        unreadCount: 1,
      ),
      const ChatRoomSummary(
        id: 'r2',
        kind: 'group_chat',
        name: 'Mathematics',
        canPost: true,
        unreadCount: 0,
      ),
    ];

    final sections = groupRoomsForStaffLanding(rooms);
    expect(sections.length, 2);
    expect(sections.first.title, 'School Announcement');
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

  test('teacher landing parses communities and contacts', () {
    final data = ChatLandingData.fromJson({
      'sections': [
        {
          'key': 'classes',
          'title': 'My Classes',
          'communities': [
            {
              'groupId': 'g1',
              'groupLabel': 'Playgroup — A',
              'displayOrder': 1,
              'section': 'A',
              'unreadCount': 3,
              'rooms': [
                {
                  'id': 'class-room',
                  'kind': 'class_announcement',
                  'name': 'Playgroup Announcements',
                  'unreadCount': 1,
                  'canPost': true,
                },
                {
                  'id': 'math-room',
                  'kind': 'group_chat',
                  'name': 'Mathematics',
                  'unreadCount': 2,
                  'canPost': true,
                },
              ],
            },
          ],
        },
        {
          'key': 'contacts',
          'title': 'Contacts',
          'contacts': [
            {
              'userId': 'admin-1',
              'name': 'Principal',
              'role': 'management',
              'branchRole': 'branch_admin',
            },
          ],
        },
      ],
      'rooms': [],
      'communities': [
        {
          'groupId': 'g1',
          'groupLabel': 'Playgroup — A',
          'displayOrder': 1,
          'section': 'A',
          'unreadCount': 3,
          'rooms': [
            {
              'id': 'class-room',
              'kind': 'class_announcement',
              'name': 'Playgroup Announcements',
              'unreadCount': 1,
              'canPost': true,
            },
          ],
        },
      ],
      'contacts': [
        {
          'userId': 'admin-1',
          'name': 'Principal',
          'role': 'management',
          'branchRole': 'branch_admin',
        },
      ],
    });

    expect(data.communities.length, 1);
    expect(data.communities.first.groupLabel, 'Playgroup — A');
    expect(data.contacts.first.roleLabel, 'Principal');
    expect(data.sections.where((s) => s.key == 'classes').first.communities.length, 1);
  });

  test('withRoomUnreadCleared zeros unread across rooms and communities', () {
    final landing = ChatLandingData.fromJson({
      'sections': [
        {
          'key': 'dm',
          'title': 'Messages',
          'rooms': [
            {'id': 'room-1', 'kind': 'direct_message', 'name': 'Alice', 'unreadCount': 3, 'canPost': true},
          ],
        },
      ],
      'rooms': [
        {'id': 'room-1', 'kind': 'direct_message', 'name': 'Alice', 'unreadCount': 3, 'canPost': true},
        {'id': 'room-2', 'kind': 'group_chat', 'name': 'Math', 'unreadCount': 2, 'canPost': true},
      ],
      'communities': [
        {
          'groupId': 'g1',
          'groupLabel': 'Class 1',
          'displayOrder': 1,
          'unreadCount': 2,
          'rooms': [
            {'id': 'room-2', 'kind': 'group_chat', 'name': 'Math', 'unreadCount': 2, 'canPost': true},
          ],
        },
      ],
    });

    final cleared = landing.withRoomUnreadCleared('room-2');
    expect(cleared.rooms.firstWhere((r) => r.id == 'room-2').unreadCount, 0);
    expect(cleared.communities.first.unreadCount, 0);
    expect(cleared.rooms.firstWhere((r) => r.id == 'room-1').unreadCount, 3);
  });

  test('landingVisibleContacts removes self and CEO', () {
    const contacts = [
      ChatContactSummary(userId: 'self', name: 'Me', role: 'branch_admin', branchRole: 'branch_admin'),
      ChatContactSummary(userId: 'ceo', name: 'CEO', role: 'super_admin', branchRole: 'branch_admin'),
      ChatContactSummary(userId: 'peer', name: 'Ms. Sarah', role: 'teacher', branchRole: 'teacher'),
    ];

    final visible = landingVisibleContacts(contacts, 'self');
    expect(visible.map((c) => c.userId), ['peer']);
  });

  test('landingVisibleDmRooms hides CEO and self threads', () {
    const rooms = [
      ChatRoomSummary(id: 'dm-ceo', kind: 'direct_message', name: 'CEO', canPost: true, unreadCount: 0),
      ChatRoomSummary(id: 'dm-peer', kind: 'direct_message', name: 'Ms. Sarah', canPost: true, unreadCount: 1),
      ChatRoomSummary(id: 'ann', kind: 'school_announcement', name: 'School', canPost: false, unreadCount: 0),
    ];
    const contacts = [
      ChatContactSummary(
        userId: 'ceo',
        name: 'CEO',
        role: 'super_admin',
        branchRole: 'branch_admin',
        dmRoomId: 'dm-ceo',
      ),
    ];

    final visible = landingVisibleDmRooms(rooms: rooms, currentUserId: 'admin-1', contacts: contacts);
    expect(visible.map((r) => r.id), ['dm-peer', 'ann']);
  });

  test('ContactPickerData filteredForUser removes self', () {
    final data = ContactPickerData.fromJson({
      'sections': [
        {
          'key': 'teachers',
          'title': 'Teachers',
          'contacts': [
            {'userId': 'self', 'name': 'Me', 'roleLabel': 'Teacher'},
            {'userId': 'other', 'name': 'Peer', 'roleLabel': 'Teacher'},
          ],
        },
      ],
      'classGroups': [],
    });

    final filtered = data.filteredForUser('self');
    expect(filtered.sections.single.contacts.single.userId, 'other');
  });
}
