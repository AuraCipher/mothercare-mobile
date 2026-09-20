import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/core/auth/jwt_utils.dart';
import 'package:mobile/core/storage/app_database.dart';
import 'package:mobile/core/storage/chat_message_cache_store.dart';
import 'package:mobile/core/storage/pending_outgoing_store.dart';
import 'package:mobile/core/storage/sqlite_kv_cache.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/chat/models/pending_outgoing_message.dart';

/// M11 §4/§19 — cross-user store isolation on one device (real SQLite/ffi).
/// Proves: B never reads A's dashboard/rooms/pending; logout wipe
/// (clearUser) removes exactly one user; session expiry is honored.

String craftJwt({required String id, required String role, required int exp}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'id': id, 'role': role, 'exp': exp})}.sig';
}

ChatMessage msg(String id, String text) {
  return ChatMessage(
    id: id,
    roomId: 'room-1',
    type: 'text',
    content: text,
    sender: const ChatMessageSender(id: 'u', name: 'U', role: 'teacher'),
    createdAt: DateTime.now().toUtc(),
  );
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqliteKvCache.testMode = false;
    ChatMessageCacheStore.testMode = false;
    PendingOutgoingStore.testMode = false;
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  group('M11 user isolation across stores', () {
    test('dashboard + bootstrap: B reads only B; logout wipe removes only A', () async {
      final kv = SqliteKvCache.instance;
      // NOTE: DashboardCacheStore.save resolves the live session (secure
      // storage); stores are exercised directly here with per-user rows.
      await kv.put(key: 'k-dash', category: 'dashboard', userId: 'userA', data: {'owner': 'A'});
      await kv.put(key: 'k-dash', category: 'dashboard', userId: 'userB', data: {'owner': 'B'});
      await kv.put(key: 'mcs_bootstrap_cache', category: 'bootstrap_student', userId: 'userA', data: {'who': 'A'});
      await kv.put(key: 'mcs_bootstrap_cache', category: 'bootstrap_student', userId: 'userB', data: {'who': 'B'});

      expect((await kv.get('k-dash', userId: 'userB'))?.data['owner'], 'B');
      expect((await kv.get('mcs_bootstrap_cache', userId: 'userB'))?.data['who'], 'B');
      expect(await kv.get('k-dash', userId: 'userC'), isNull);

      // Logout wipe for A (what SessionStorage.clear → clearUser does).
      await AppDatabase.instance.clearUser('userA');
      expect(await kv.get('k-dash', userId: 'userA'), isNull);
      expect(await kv.get('mcs_bootstrap_cache', userId: 'userA'), isNull);
      expect((await kv.get('k-dash', userId: 'userB'))?.data['owner'], 'B');
      await AppDatabase.instance.clearUser('userB');
    });

    test('chat rooms + pending: same room id, strictly per-user rows', () async {
      final rooms = ChatMessageCacheStore.instance;
      final pending = PendingOutgoingStore.instance;
      await rooms.saveRoom(userId: 'userA', roomId: 'room-1', messages: [msg('m1', 'A secret')]);
      await rooms.saveRoom(userId: 'userB', roomId: 'room-1', messages: [msg('m2', 'B secret')]);
      await pending.saveRoom(
        userId: 'userA',
        roomId: 'room-1',
        pending: [
          const PendingOutgoingMessage(localId: 'send:k1', type: 'text', content: 'A pending'),
        ],
      );

      final gotB = await rooms.loadRoom(userId: 'userB', roomId: 'room-1');
      expect(gotB!.messages.map((m) => m.content), ['B secret']);
      final gotA = await rooms.loadRoom(userId: 'userA', roomId: 'room-1');
      expect(gotA!.messages.map((m) => m.content), ['A secret']);
      expect(await pending.loadRoom(userId: 'userB', roomId: 'room-1'), isEmpty);
      expect((await pending.loadRoom(userId: 'userA', roomId: 'room-1')).map((p) => p.content), ['A pending']);

      await AppDatabase.instance.clearUser('userA');
      expect(await rooms.loadRoom(userId: 'userA', roomId: 'room-1'), isNull);
      expect((await rooms.loadRoom(userId: 'userB', roomId: 'room-1'))!.messages, hasLength(1));
      await AppDatabase.instance.clearUser('userB');
    });
  });

  group('M11 session expiry + role routing predicates', () {
    test('expired JWT decodes as expired (readSession clears + returns null)', () {
      final past = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final future = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final expired = decodeJwtPayload(craftJwt(id: 'u1', role: 'student', exp: past));
      final live = decodeJwtPayload(craftJwt(id: 'u1', role: 'student', exp: future));
      expect(expired, isNotNull);
      expect(expired!.isExpired, isTrue);
      expect(live!.isExpired, isFalse);
      expect(decodeJwtPayload('not-a-jwt'), isNull);
    });

    test('role predicates route every real role to exactly one surface', () {
      // Mobile shells.
      expect(isMobileAppRole('student'), isTrue);
      expect(isMobileAppRole('teacher'), isTrue);
      expect(isMobileAppRole('parent'), isTrue);
      expect(isMobileAppRole('branch_admin'), isTrue);
      expect(isMobileAppRole('sub_admin'), isTrue);
      expect(isMobileAppRole('management'), isTrue);
      // Web-only.
      expect(isMobileAppRole('super_admin'), isFalse);
      expect(isWebOnlyRole('super_admin'), isTrue);
      expect(isWebOnlyRole('management'), isFalse);
      // Staff-admin subset.
      expect(isStaffAdminRole('branch_admin'), isTrue);
      expect(isStaffAdminRole('teacher'), isFalse);
      expect(isStaffAdminRole('student'), isFalse);
    });
  });
}
