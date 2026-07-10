# Mobile E2E tests

Integration tests for the Flutter chat app using `integration_test`.

## CI / VM runs (no device)

Runs on the Flutter test VM with a mock HTTP client — no backend or emulator required:

```bash
cd mobile
flutter test test/e2e/ --concurrency=1
```

## Device integration tests

Same suites under `integration_test/` for on-device runs (Android emulator / iOS simulator):

```bash
cd mobile
flutter test integration_test/student_chat_e2e_test.dart -d <device_id>
```

## Mock E2E (default — no backend)

Uses a built-in HTTP mock. Safe for CI and local runs.

```bash
cd mobile
flutter pub get
flutter test test/e2e/ --concurrency=1

# Or on a connected device:
flutter test integration_test/login_e2e_test.dart -d <device_id>
flutter test integration_test/student_chat_e2e_test.dart -d <device_id>
flutter test integration_test/teacher_admin_chat_e2e_test.dart -d <device_id>
flutter test integration_test/chat_room_e2e_test.dart -d <device_id>

# All mock integration suites on device
flutter test integration_test/ -d <device_id>
```

### Coverage

| Suite | Flows |
|-------|--------|
| `login_e2e_test.dart` | Form validation, invalid credentials |
| `student_chat_e2e_test.dart` | Login → landing → tabs → room → logout |
| `teacher_admin_chat_e2e_test.dart` | Teacher + admin portal navigation & rooms |
| `chat_room_e2e_test.dart` | Read-only channel, message list, cache re-open |

## Live E2E (real backend + demo seed)

Requires backend running and demo data:

```bash
cd backend && npm run db:reset:demo && npm run dev
```

Android emulator API URL:

```bash
cd mobile
flutter test integration_test/live_demo_e2e_test.dart \
  --dart-define=E2E_LIVE=true \
  --dart-define=API_BASE_URL=http://10.0.2.2:5000 \
  --dart-define=E2E_API_URL=http://10.0.2.2:5000
```

Physical device: replace `10.0.2.2` with your machine LAN IP.

### Demo accounts

| Role | Username | Password |
|------|----------|----------|
| Student | `demo_pg_ahmed` | `DemoStudent@123` |
| Teacher | `demo_teacher_playgroup` | `DemoTeacher@123` |
| Admin | `demo_admin` | `DemoAdmin@123` |

## Device / emulator runs

To run on a connected device (slower, closer to production):

```bash
flutter test integration_test/student_chat_e2e_test.dart -d <device_id>
```

## Test keys

Stable widget keys live in `lib/testing/e2e_keys.dart` and are attached to login fields and chat room tiles.
