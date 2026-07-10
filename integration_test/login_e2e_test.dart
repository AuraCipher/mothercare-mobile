import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';
import 'package:mobile/testing/e2e_keys.dart';

import 'support/e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login E2E — validation', () {
    testWidgets('shows sign-in screen and validates empty fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const LoginScreen(),
        ),
      );

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Mother Care School'), findsOneWidget);
      expect(find.text('Sign in with your school credentials'), findsOneWidget);

      await tester.tap(find.byKey(E2eKeys.loginSubmit));
      await tester.pumpAndSettle();

      expect(find.text('Enter your username, email, or phone'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('rejects password shorter than minimum', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const LoginScreen(),
        ),
      );

      await tester.enterText(find.byKey(E2eKeys.loginIdentifier), 'demo_user');
      await tester.enterText(find.byKey(E2eKeys.loginPassword), 'short');
      await tester.tap(find.byKey(E2eKeys.loginSubmit));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });
  });

  group('Login E2E — mock API', () {
    late E2eHttpMock httpMock;

    setUp(() {
      httpMock = E2eHttpMock(MockApiRouter())..install();
    });

    tearDown(() {
      httpMock.uninstall();
    });

    testWidgets('shows error for invalid credentials', (tester) async {
      await initE2eBinding();
      await pumpMcsApp(tester);
      await pumpUntilFound(tester, find.byKey(E2eKeys.loginIdentifier));

      await loginViaUi(tester, identifier: 'wrong_user', password: 'WrongPass@123');
      await pumpUntilFound(tester, find.textContaining('Incorrect username'));

      expect(find.text('School Announcement'), findsNothing);
    });
  });
}
