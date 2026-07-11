import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/jwt_utils.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/student/models/student_bootstrap.dart';
import '../../features/chat/models/chat_models.dart';
import '../../features/teacher/models/teacher_bootstrap.dart';
import '../../features/staff/models/staff_bootstrap.dart';
import 'cache_constants.dart';
import 'cached_envelope.dart';
import 'app_database.dart';
import 'sqlite_kv_cache.dart';

const _kToken = 'mcs_auth_token';
const _kUser = 'mcs_auth_user';
const _kPush = 'mcs_push_crypto';
const _kBranchId = 'mcs_active_branch_id';
const _kAcademicYearId = 'mcs_academic_year_id';
const _kBootstrapCache = 'mcs_bootstrap_cache';
const _kChatLandingCache = 'mcs_chat_landing_cache';
const _kTeacherBootstrapCache = 'mcs_teacher_bootstrap_cache';
const _kStaffBootstrapCache = 'mcs_staff_bootstrap_cache';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final SqliteKvCache _kv = SqliteKvCache.instance;

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

  Future<void> saveActiveBranchId(String id) => _storage.write(key: _kBranchId, value: id);

  Future<void> saveAcademicYearId(String id) => _storage.write(key: _kAcademicYearId, value: id);

  Future<String?> getAcademicYearId() => _storage.read(key: _kAcademicYearId);

  Future<PushCryptoMaterial?> readPushCrypto() async {
    final raw = await _storage.read(key: _kPush);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PushCryptoMaterial.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

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
    final session = await readSession();
    final userId = session?.payload.id;
    final branchId = await getActiveBranchId();

    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPush);
    await _storage.delete(key: _kBranchId);
    await _storage.delete(key: _kAcademicYearId);
    await _storage.delete(key: _kBootstrapCache);
    await _storage.delete(key: _kChatLandingCache);
    await _storage.delete(key: _kTeacherBootstrapCache);
    await _storage.delete(key: _kStaffBootstrapCache);

    if (userId != null) {
      await AppDatabase.instance.clearUser(userId);
      await _storage.delete(
        key: chatLandingCacheKey(scope: ChatLandingScope.student, userId: userId),
      );
      await _storage.delete(
        key: chatLandingCacheKey(scope: ChatLandingScope.teacher, userId: userId),
      );
      if (branchId != null) {
        await _storage.delete(
          key: chatLandingCacheKey(
            scope: ChatLandingScope.admin,
            userId: userId,
            branchId: branchId,
          ),
        );
      }
    }
  }

  Future<void> _saveKv(String key, String category, String userId, Map<String, dynamic> data) async {
    await _kv.put(key: key, category: category, userId: userId, data: data);
  }

  Future<CachedEnvelope?> _readKv(String key, {String? legacySecureKey}) async {
    var envelope = await _kv.get(key);
    if (envelope != null) return envelope;
    if (legacySecureKey == null) return null;
    final raw = await _storage.read(key: legacySecureKey);
    if (raw == null || raw.isEmpty) return null;
    envelope = CachedEnvelope.parse(raw);
    if (envelope != null) {
      final userId = (await readSession())?.payload.id;
      if (userId != null) {
        await _kv.put(key: key, category: 'legacy', userId: userId, data: envelope.data);
        await _storage.delete(key: legacySecureKey);
      }
    }
    return envelope;
  }

  Future<void> saveBootstrapCache(StudentBootstrap bootstrap) async {
    final userId = (await readSession())?.payload.id;
    if (userId == null) return;
    await _saveKv(_kBootstrapCache, 'bootstrap_student', userId, bootstrap.toJson());
  }

  Future<StudentBootstrap?> readBootstrapCache() async {
    final envelope = await _readKv(_kBootstrapCache, legacySecureKey: _kBootstrapCache);
    if (envelope != null) {
      if (envelope.isExpired(CacheTtls.bootstrap)) return null;
      try {
        return StudentBootstrap.fromJson(envelope.data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveChatLandingCache(
    ChatLandingData landing, {
    required ChatLandingScope scope,
    required String userId,
    String? branchId,
  }) async {
    final key = chatLandingCacheKey(scope: scope, userId: userId, branchId: branchId);
    await _saveKv(key, 'landing_${scope.name}', userId, landing.toJson());
  }

  Future<ChatLandingData?> readChatLandingCache({
    required ChatLandingScope scope,
    required String userId,
    String? branchId,
  }) async {
    final key = chatLandingCacheKey(scope: scope, userId: userId, branchId: branchId);
    var envelope = await _readKv(key, legacySecureKey: key);
    if (envelope == null && scope == ChatLandingScope.student) {
      envelope = await _readKv(key, legacySecureKey: _kChatLandingCache);
    }
    if (envelope != null) {
      if (envelope.isExpired(CacheTtls.landing)) return null;
      try {
        return ChatLandingData.fromJson(envelope.data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveTeacherBootstrapCache(TeacherBootstrap bootstrap) async {
    final userId = (await readSession())?.payload.id;
    if (userId == null) return;
    await _saveKv(_kTeacherBootstrapCache, 'bootstrap_teacher', userId, bootstrap.toJson());
  }

  Future<TeacherBootstrap?> readTeacherBootstrapCache() async {
    final envelope = await _readKv(_kTeacherBootstrapCache, legacySecureKey: _kTeacherBootstrapCache);
    if (envelope != null) {
      if (envelope.isExpired(CacheTtls.bootstrap)) return null;
      try {
        return TeacherBootstrap.fromJson(envelope.data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveStaffBootstrapCache(StaffBootstrap bootstrap) async {
    final userId = (await readSession())?.payload.id;
    if (userId == null) return;
    await _saveKv(_kStaffBootstrapCache, 'bootstrap_staff', userId, bootstrap.toJson());
  }

  Future<StaffBootstrap?> readStaffBootstrapCache() async {
    final envelope = await _readKv(_kStaffBootstrapCache, legacySecureKey: _kStaffBootstrapCache);
    if (envelope != null) {
      if (envelope.isExpired(CacheTtls.bootstrap)) return null;
      try {
        return StaffBootstrap.fromJson(envelope.data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class StoredSession {
  StoredSession({required this.token, required this.payload, this.user});

  final String token;
  final JwtPayload payload;
  final AuthUser? user;
}
