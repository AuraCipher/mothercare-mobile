import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/testing/e2e_keys.dart';
import 'package:mobile/core/storage/sqlite_kv_cache.dart';
import 'package:mobile/core/storage/chat_message_cache_store.dart';
import 'package:mobile/core/storage/pending_outgoing_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'e2e_credentials.dart' show E2eCredentials;
export 'mock_api_router.dart' show E2eCredentials, E2eIds;
export 'e2e_config.dart';
export 'e2e_http_mock.dart';
export 'e2e_seed.dart';
export 'mock_api_router.dart';

class _TestPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '/tmp/mcs_e2e';

  @override
  Future<String?> getTemporaryPath() async => '/tmp/mcs_e2e';
}

Future<void> initE2eBinding() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = _TestPathProvider();
  SqliteKvCache.testMode = true;
  ChatMessageCacheStore.testMode = true;
  PendingOutgoingStore.testMode = true;
}

Future<void> pumpMcsApp(WidgetTester tester) async {
  await tester.pumpWidget(const McsApp());
  await tester.pump();
}

Future<void> loginViaUi(
  WidgetTester tester, {
  required String identifier,
  required String password,
}) async {
  final identifierField = find.byKey(E2eKeys.loginIdentifier);
  final passwordField = find.byKey(E2eKeys.loginPassword);

  expect(identifierField, findsOneWidget);
  await tester.enterText(identifierField, identifier);
  await tester.enterText(passwordField, password);
  await tester.tap(find.byKey(E2eKeys.loginSubmit));
  await _waitForRealAsync(tester, pumps: 8);
}

/// Pump until [finder] appears or [timeout] elapses.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

Future<void> tapNavLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _waitForRealAsync(WidgetTester tester, {int pumps = 5}) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openChatRoom(
  WidgetTester tester,
  String roomId, {
  bool waitForMessages = true,
}) async {
  await tester.tap(find.byKey(ValueKey('e2e_chat_room_$roomId')));
  await tester.pump();
  await pumpUntilFound(
    tester,
    find.text('Read-only channel'),
    timeout: const Duration(seconds: 5),
  );
  if (!waitForMessages) return;

  await pumpUntilFound(
    tester,
    find.text('Welcome to the demo channel.'),
    timeout: const Duration(seconds: 8),
  );
}

Future<void> logoutFromProfile(WidgetTester tester) async {
  await tapNavLabel(tester, 'Profile');
  await tester.tap(find.text('Logout'));
  await _waitForRealAsync(tester, pumps: 15);
  await pumpUntilFound(
    tester,
    find.text('Sign In'),
    timeout: const Duration(seconds: 8),
  );
}

/// Standard demo student login + wait for chats landing.
Future<void> loginDemoStudent(WidgetTester tester) async {
  await loginViaUi(
    tester,
    identifier: E2eCredentials.studentId,
    password: E2eCredentials.studentPassword,
  );
  await pumpUntilFound(tester, find.text('School Announcement'));
}

Future<void> loginDemoTeacher(WidgetTester tester) async {
  await loginViaUi(
    tester,
    identifier: E2eCredentials.teacherId,
    password: E2eCredentials.teacherPassword,
  );
  await pumpUntilFound(tester, find.text('School Announcement'));
}

Future<void> loginDemoAdmin(WidgetTester tester) async {
  await loginViaUi(
    tester,
    identifier: E2eCredentials.adminId,
    password: E2eCredentials.adminPassword,
  );
  await pumpUntilFound(tester, find.text('School Announcement'));
}
