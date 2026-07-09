class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.role,
    this.username,
    this.email,
    this.phone,
    this.status,
  });

  final String id;
  final String name;
  final String role;
  final String? username;
  final String? email;
  final String? phone;
  final String? status;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      username: json['username'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'username': username,
        'email': email,
        'phone': phone,
        'status': status,
      };
}

class PushCryptoMaterial {
  const PushCryptoMaterial({
    required this.algorithm,
    required this.keyVersion,
    required this.key,
  });

  final String algorithm;
  final int keyVersion;
  final String key;

  factory PushCryptoMaterial.fromJson(Map<String, dynamic> json) {
    return PushCryptoMaterial(
      algorithm: json['algorithm'] as String? ?? 'AES-256-GCM',
      keyVersion: json['keyVersion'] is int
          ? json['keyVersion'] as int
          : int.tryParse('${json['keyVersion']}') ?? 1,
      key: json['key'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'keyVersion': keyVersion,
        'key': key,
      };
}

class LoginResponse {
  const LoginResponse({
    required this.success,
    required this.token,
    required this.user,
    this.push,
    this.message,
  });

  final bool success;
  final String token;
  final AuthUser user;
  final PushCryptoMaterial? push;
  final String? message;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['success'] as bool? ?? false,
      token: json['token'] as String? ?? '',
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      push: json['push'] != null
          ? PushCryptoMaterial.fromJson(json['push'] as Map<String, dynamic>)
          : null,
      message: json['message'] as String?,
    );
  }
}
