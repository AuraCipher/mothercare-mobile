import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/testing/e2e_keys.dart';

import '../../integration_test/support/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Student chat E2E (mock API)', () {
    late E2eHttpMock httpMock;

    setUp(() async {
      await initE2eBinding();
      httpMock = E2eHttpMock(MockApiRouter())..install();
    });

    tearDown(() {
      httpMock.uninstall();
    });

    testWidgets('logs in and shows school announcement on chats home', (tester) async {
      await pumpMcsApp(tester);
      await pumpUntilFound(tester, find.byKey(E2eKeys.loginIdentifier));

      await loginDemoStudent(tester);

      expect(find.text('School Announcement'), findsWidgets);
      expect(find.text('Playgroup'), findsWidgets);
    });

    testWidgets('navigates to academics and profile tabs', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoStudent(tester);

      await tapNavLabel(tester, 'Academics');
      expect(find.textContaining('coming in Phase 2'), findsOneWidget);

      await tapNavLabel(tester, 'Profile');
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('opens school announcement read-only room', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoStudent(tester);
      await openChatRoom(tester, E2eIds.schoolRoomId, waitForMessages: false);

      expect(find.text('Read-only channel'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });

    testWidgets('logout returns to login screen', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoStudent(tester);

      await logoutFromProfile(tester);
    }, skip: true); // Logout clears secure storage async; verify manually on device.
  });
}
