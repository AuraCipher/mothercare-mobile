/// TTL defaults for on-device chat caches.
class CacheTtls {
  static const landing = Duration(minutes: 30);
  static const bootstrap = Duration(hours: 24);
  static const messageRoom = Duration(days: 30);
}

enum ChatLandingScope {
  student,
  teacher,
  admin,
}

String chatLandingCacheKey({
  required ChatLandingScope scope,
  required String userId,
  String? branchId,
}) {
  switch (scope) {
    case ChatLandingScope.student:
      return 'mcs_chat_landing_student_$userId';
    case ChatLandingScope.teacher:
      return 'mcs_chat_landing_teacher_$userId';
    case ChatLandingScope.admin:
      final branch = branchId ?? 'default';
      return 'mcs_chat_landing_admin_${userId}_$branch';
  }
}
