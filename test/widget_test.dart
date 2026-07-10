import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('Login screen shows sign in', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const LoginScreen(),
      ),
    );
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Mother Care School'), findsOneWidget);
    expect(find.text('Sign in with your school credentials'), findsOneWidget);
  });
}
