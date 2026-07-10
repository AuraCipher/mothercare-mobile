import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/testing/e2e_keys.dart';

import 'support/e2e_config.dart';
import 'support/e2e_harness.dart';

/// Runs against a real backend with demo seed:
///   cd backend && npm run db:reset:demo && npm run dev
///
/// flutter test integration_test/live_demo_e2e_test.dart \
///   --dart-define=E2E_LIVE=true \
///   --dart-define=E2E_API_URL=http://10.0.2.2:5000 \
///   --dart-define=API_BASE_URL=http://10.0.2.2:5000
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Live demo E2E', () {
    testWidgets('student demo login reaches chat landing', (tester) async {
      if (!E2eConfig.live) {
        // Skip body — test marked skipped via return after expect in flutter 3.16+
        return;
      }

      await initE2eBinding();
      await pumpMcsApp(tester);
      await pumpUntilFound(tester, find.byKey(E2eKeys.loginIdentifier));

      await loginViaUi(
        tester,
        identifier: E2eCredentials.studentId,
        password: E2eCredentials.studentPassword,
      );

      await pumpUntilFound(
        tester,
        find.text('School Announcement'),
        timeout: const Duration(seconds: 30),
      );
      expect(find.textContaining('Sign In'), findsNothing);
    }, skip: !E2eConfig.live);
  });
}
