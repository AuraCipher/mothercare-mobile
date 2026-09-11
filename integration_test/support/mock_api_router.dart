import 'dart:convert';

import 'fake_jwt.dart';

/// Demo-style accounts matching MCS-DEMO seed naming.
abstract final class E2eCredentials {
  static const studentId = 'demo_pg_ahmed';
  static const studentPassword = 'DemoStudent@123';

  static const teacherId = 'demo_teacher_playgroup';
  static const teacherPassword = 'DemoTeacher@123';

  static const adminId = 'demo_admin';
  static const adminPassword = 'DemoAdmin@123';
}

abstract final class E2eIds {
  static const academicYearId = 'ay-demo-1';
  static const branchId = 'branch-demo-1';
  static const schoolRoomId = 'room-school-ann';
  static const classRoomId = 'room-class-ann';
  static const groupRoomId = 'room-math-group';
}

/// Routes HTTP requests to canned JSON for offline E2E runs.
class MockApiRouter {
  MockApiRouter();

  final Map<String, _Account> _accounts = {
    E2eCredentials.studentId: _Account(
      id: 'user-student-1',
      role: 'student',
      name: 'Ahmed Khan',
      token: buildFakeJwt(id: 'user-student-1', role: 'student', name: 'Ahmed Khan'),
    ),
    E2eCredentials.teacherId: _Account(
      id: 'user-teacher-1',
      role: 'teacher',
      name: 'Ms. Nadia',
      token: buildFakeJwt(id: 'user-teacher-1', role: 'teacher', name: 'Ms. Nadia'),
    ),
    E2eCredentials.adminId: _Account(
      id: 'user-admin-1',
      role: 'branch_admin',
      name: 'Demo Principal',
      token: buildFakeJwt(id: 'user-admin-1', role: 'branch_admin', name: 'Demo Principal'),
    ),
  };

  ({int status, String body, Map<String, String> headers}) route(String method, Uri uri, String? body) {
    final path = uri.path;

    if (method == 'POST' && path == '/auth/login') {
      return _login(body);
    }
    if (method == 'GET' && path == '/student/bootstrap') {
      return _ok(_studentBootstrap());
    }
    if (method == 'GET' && path == '/student/chat/landing') {
      return _ok(_studentLanding());
    }
    if (method == 'GET' && path == '/me/academic-year') {
      return _ok({
        'success': true,
        'data': {'id': E2eIds.academicYearId, 'label': '2025–26'},
      });
    }
    if (method == 'GET' && path == '/me/branches') {
      return _ok({
        'success': true,
        'data': [
          {
            'id': E2eIds.branchId,
            'name': 'Mother Care Demo Campus',
            'role': 'branch_admin',
          },
        ],
      });
    }
    if (method == 'GET' && path == '/teacher/bootstrap') {
      return _ok(_teacherBootstrap());
    }
    if (method == 'GET' && path == '/teacher/chat/landing') {
      return _ok(_teacherLanding());
    }
    if (method == 'GET' && path == '/staff/chat/landing') {
      return _ok(_staffLanding());
    }
    if (method == 'GET' && path.startsWith('/chat/rooms/') && path.endsWith('/messages')) {
      final roomId = path.split('/')[3];
      return _ok(_roomMessages(roomId));
    }
    if (method == 'GET' && path == '/student/profile') {
      return _ok({
        'success': true,
        'data': {
          'name': 'Ahmed Khan',
          'rollNumber': 'PG-01',
          'email': 'ahmed@demo.com',
          'username': 'demo_pg_ahmed',
        },
      });
    }
    if (method == 'GET' && path == '/staff/campus/overview') {
      return _ok({
        'success': true,
        'data': {
          'studentCount': 120,
          'classCount': 5,
          'teacherCount': 12,
          'staffCount': 8,
        },
      });
    }
    if (method == 'GET' && path == '/staff/campus/fees') {
      return _ok({
        'success': true,
        'data': {
          'month': 7,
          'year': 2026,
          'totalCollected': 500000,
          'totalDue': 150000,
          'pendingCount': 30,
          'collectionRate': 77,
        },
      });
    }
    if (method == 'GET' && path == '/staff/campus/attendance') {
      return _ok({
        'success': true,
        'data': {
          'date': '2026-07-10',
          'summary': {'present': 100, 'absent': 15, 'late': 5},
          'classes': [
            {'groupName': 'Playgroup', 'present': 25, 'total': 30},
          ],
        },
      });
    }
    if (method == 'GET' && path == '/staff/campus/staff') {
      return _ok({
        'success': true,
        'data': [
          {'name': 'Ms. Nadia', 'branchRole': 'Teacher', 'userRole': 'teacher', 'status': 'active'},
          {'name': 'Mr. Khan', 'branchRole': 'Admin', 'userRole': 'branch_admin', 'status': 'active'},
        ],
      });
    }
    if (method == 'GET' && path == '/staff/campus/results') {
      return _ok({
        'success': true,
        'data': [
          {'name': 'Mid-term', 'examCount': 5, 'startDate': '2026-06-15'},
        ],
      });
    }

    return (
      status: 404,
      body: jsonResponse({'success': false, 'message': 'E2E mock: no handler for $method $path'}),
      headers: {'content-type': 'application/json'},
    );
  }

  ({int status, String body, Map<String, String> headers}) _login(String? rawBody) {
    final map = rawBody == null ? <String, dynamic>{} : jsonDecode(rawBody) as Map<String, dynamic>;
    final identifier = map['identifier'] as String? ?? '';
    final password = map['password'] as String? ?? '';
    final account = _accounts[identifier];
    if (account == null) {
      return (
        status: 401,
        body: jsonResponse({'success': false, 'message': 'Invalid credentials'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (password != _passwordFor(identifier)) {
      return (
        status: 401,
        body: jsonResponse({'success': false, 'message': 'Invalid credentials'}),
        headers: {'content-type': 'application/json'},
      );
    }
    return _ok({
      'success': true,
      'token': account.token,
      'user': {
        'id': account.id,
        'name': account.name,
        'role': account.role,
        'username': identifier,
      },
      'push': {
        'algorithm': 'AES-256-GCM',
        'keyVersion': 1,
        'key': base64Encode(List<int>.filled(32, 7)),
      },
    });
  }

  String _passwordFor(String identifier) {
    switch (identifier) {
      case E2eCredentials.studentId:
        return E2eCredentials.studentPassword;
      case E2eCredentials.teacherId:
        return E2eCredentials.teacherPassword;
      case E2eCredentials.adminId:
        return E2eCredentials.adminPassword;
      default:
        return '';
    }
  }

  Map<String, dynamic> _studentBootstrap() => {
        'success': true,
        'data': {
          'academicYear': {'id': E2eIds.academicYearId, 'label': '2025–26'},
          'branch': {'name': 'Mother Care Demo Campus'},
          'user': {'name': 'Ahmed Khan'},
          'student': {
            'name': 'Ahmed Khan',
            'groupLabel': 'Playgroup',
            'rollNumber': 'PG-01',
          },
        },
      };

  Map<String, dynamic> _landingRooms() => {
        'rooms': [
          {
            'id': E2eIds.schoolRoomId,
            'kind': 'school_announcement',
            'name': 'School Announcement',
            'canPost': false,
            'unreadCount': 2,
            'lastMessageAt': '2026-07-10T08:00:00.000Z',
          },
          {
            'id': E2eIds.classRoomId,
            'kind': 'class_announcement',
            'name': 'Playgroup Announcement',
            'canPost': false,
            'unreadCount': 0,
            'lastMessageAt': '2026-07-09T12:00:00.000Z',
          },
          {
            'id': E2eIds.groupRoomId,
            'kind': 'group_chat',
            'name': 'Mathematics',
            'canPost': true,
            'unreadCount': 1,
            'lastMessageAt': '2026-07-10T09:30:00.000Z',
          },
        ],
        'sections': [
          {
            'key': 'school',
            'title': 'School Announcement',
            'rooms': [
              {
                'id': E2eIds.schoolRoomId,
                'kind': 'school_announcement',
                'name': 'School Announcement',
                'canPost': false,
                'unreadCount': 2,
              },
            ],
          },
          {
            'key': 'class',
            'title': 'Playgroup',
            'rooms': [
              {
                'id': E2eIds.classRoomId,
                'kind': 'class_announcement',
                'name': 'Playgroup Announcement',
                'canPost': false,
                'unreadCount': 0,
              },
              {
                'id': E2eIds.groupRoomId,
                'kind': 'group_chat',
                'name': 'Mathematics',
                'canPost': true,
                'unreadCount': 1,
              },
            ],
          },
        ],
      };

  Map<String, dynamic> _studentLanding() => {
        'success': true,
        'data': _landingRooms(),
      };

  Map<String, dynamic> _teacherBootstrap() => {
        'success': true,
        'data': {
          'academicYear': {'id': E2eIds.academicYearId, 'label': '2025–26'},
          'branch': {'id': E2eIds.branchId, 'name': 'Mother Care Demo Campus'},
          'user': {'name': 'Ms. Nadia'},
          'portal': {'isHod': false, 'assignmentCount': 1},
          'assignments': [
            {
              'id': 'assign-1',
              'groupId': 'group-pg',
              'subjectId': 'sub-math',
              'isClassTeacher': true,
              'group': {'id': 'group-pg', 'name': 'Playgroup', 'section': 'A'},
              'subject': {'id': 'sub-math', 'name': 'Mathematics'},
            },
          ],
        },
      };

  Map<String, dynamic> _teacherLanding() => {
        'success': true,
        'data': {
          ..._landingRooms(),
          'communities': [
            {
              'groupId': 'group-pg',
              'groupLabel': 'Playgroup · A',
              'displayOrder': 1,
              'unreadCount': 1,
              'rooms': [
                {
                  'id': E2eIds.classRoomId,
                  'kind': 'class_announcement',
                  'name': 'Class Announcement',
                  'canPost': true,
                  'unreadCount': 0,
                },
              ],
            },
          ],
        },
      };

  Map<String, dynamic> _staffLanding() => {
        'success': true,
        'data': {
          ..._landingRooms(),
          'communities': [
            {
              'groupId': 'group-pg',
              'groupLabel': 'Playgroup · A',
              'displayOrder': 1,
              'unreadCount': 0,
              'rooms': [
                {
                  'id': E2eIds.classRoomId,
                  'kind': 'class_announcement',
                  'name': 'Class Announcement',
                  'canPost': true,
                  'unreadCount': 0,
                },
              ],
            },
          ],
        },
      };

  Map<String, dynamic> _roomMessages(String roomId) => {
        'success': true,
        'data': [
          {
            'id': 'msg-1',
            'roomId': roomId,
            'type': 'text',
            'content': 'Welcome to the demo channel.',
            'sender': {'id': 'user-teacher-1', 'name': 'Ms. Nadia', 'role': 'teacher'},
            'createdAt': '2026-07-10T10:00:00.000Z',
          },
          {
            'id': 'msg-2',
            'roomId': roomId,
            'type': 'text',
            'content': 'Please check the latest notice.',
            'sender': {'id': 'user-admin-1', 'name': 'Demo Principal', 'role': 'branch_admin'},
            'createdAt': '2026-07-10T10:05:00.000Z',
          },
        ],
      };

  ({int status, String body, Map<String, String> headers}) _ok(Map<String, dynamic> body) => (
        status: 200,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
}

class _Account {
  const _Account({
    required this.id,
    required this.role,
    required this.name,
    required this.token,
  });

  final String id;
  final String role;
  final String name;
  final String token;
}
