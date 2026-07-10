import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Teacher chat E2E (mock API)', () {
    late E2eHttpMock httpMock;

    setUp(() async {
      await initE2eBinding();
      httpMock = E2eHttpMock(MockApiRouter())..install();
    });

    tearDown(() {
      httpMock.uninstall();
    });

    testWidgets('logs in and shows portal chat landing', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoTeacher(tester);

      expect(find.text('School Announcement'), findsWidgets);
      expect(find.text('My Classes'), findsOneWidget);
    });

    testWidgets('switches to classes workspace tab', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoTeacher(tester);

      await tapNavLabel(tester, 'Classes');
      expect(find.textContaining('Playgroup'), findsWidgets);
    });

    testWidgets('opens school announcement from teacher landing', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoTeacher(tester);

      await openChatRoom(tester, E2eIds.schoolRoomId, waitForMessages: false);
      expect(find.text('Read-only channel'), findsOneWidget);
    });
  });

  group('Admin staff chat E2E (mock API)', () {
    late E2eHttpMock httpMock;

    setUp(() async {
      await initE2eBinding();
      httpMock = E2eHttpMock(MockApiRouter())..install();
    });

    tearDown(() {
      httpMock.uninstall();
    });

    testWidgets('logs in as branch admin and shows chat landing', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoAdmin(tester);

      expect(find.text('School Announcement'), findsWidgets);
      expect(find.text('Class Communities'), findsOneWidget);
    });

    testWidgets('admin can open campus workspace tab', (tester) async {
      await pumpMcsApp(tester);
      await loginDemoAdmin(tester);

      await tapNavLabel(tester, 'Campus');
      expect(find.text('Staff & students'), findsOneWidget);
    });
  });
}
