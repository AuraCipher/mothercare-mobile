import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/jwt_utils.dart';
import '../../features/auth/models/auth_models.dart';

const _kToken = 'mcs_auth_token';
const _kUser = 'mcs_auth_user';
const _kPush = 'mcs_push_crypto';
const _kBranchId = 'mcs_active_branch_id';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> saveSession(LoginResponse response) async {
    await _storage.write(key: _kToken, value: response.token);
    await _storage.write(key: _kUser, value: jsonEncode(response.user.toJson()));
    if (response.push != null) {
      await _storage.write(key: _kPush, value: jsonEncode(response.push!.toJson()));
    }
    final payload = decodeJwtPayload(response.token);
    if (payload != null && payload.branchIds.isNotEmpty) {
      await _storage.write(key: _kBranchId, value: payload.branchIds.first);
    }
  }

  Future<String?> getToken() => _storage.read(key: _kToken);

  Future<String?> getActiveBranchId() => _storage.read(key: _kBranchId);

  Future<StoredSession?> readSession() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    final payload = decodeJwtPayload(token);
    if (payload == null || payload.isExpired) {
      await clear();
      return null;
    }
    final userJson = await _storage.read(key: _kUser);
    AuthUser? user;
    if (userJson != null) {
      user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    }
    return StoredSession(token: token, payload: payload, user: user);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPush);
    await _storage.delete(key: _kBranchId);
  }
}

class StoredSession {
  StoredSession({required this.token, required this.payload, this.user});

  final String token;
  final JwtPayload payload;
  final AuthUser? user;
}
