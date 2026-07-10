import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat room E2E (mock API)', () {
    late E2eHttpMock httpMock;

    setUp(() async {
      await initE2eBinding();
      httpMock = E2eHttpMock(MockApiRouter())..install();
    });

    tearDown(() {
      httpMock.uninstall();
    });

    testWidgets('student sees composer hidden in read-only school channel', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoStudent(tester);
      await openChatRoom(tester, E2eIds.schoolRoomId, waitForMessages: false);

      expect(find.text('Read-only channel'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });
  });
}
