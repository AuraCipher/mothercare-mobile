import 'dart:convert';

class JwtPayload {
  JwtPayload({
    required this.id,
    required this.role,
    required this.name,
    this.branchIds = const [],
    this.exp,
  });

  final String id;
  final String role;
  final String name;
  final List<String> branchIds;
  final int? exp;

  bool get isExpired {
    if (exp == null) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec >= exp!;
  }
}

JwtPayload? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final normalized = base64Url.normalize(parts[1]);
    final jsonStr = utf8.decode(base64Url.decode(normalized));
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    final branchRaw = map['branchIds'];
    return JwtPayload(
      id: map['id'] as String? ?? '',
      role: map['role'] as String? ?? '',
      name: map['name'] as String? ?? '',
      branchIds: branchRaw is List ? branchRaw.map((e) => e.toString()).toList() : [],
      exp: map['exp'] is int ? map['exp'] as int : int.tryParse('${map['exp']}'),
    );
  } catch (_) {
    return null;
  }
}

String landingRouteForRole(String role) {
  switch (role) {
    case 'student':
      return '/student';
    case 'teacher':
      return '/teacher';
    case 'parent':
      return '/student';
    default:
      return '/unsupported';
  }
}

bool isMobileAppRole(String role) {
  return role == 'student' || role == 'teacher' || role == 'parent' || isStaffAdminRole(role);
}

bool isStaffAdminRole(String role) {
  return role == 'branch_admin' || role == 'sub_admin' || role == 'management';
}

/// CEO / web-only staff — must use the admin web portal, not the mobile app.
bool isWebOnlyRole(String role) {
  return role == 'super_admin';
}
