# Mobile CI test matrix

Run locally before push:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test                    # unit/widget tests in test/
```

## Unit tests (`test/`)

| File | Covers |
|------|--------|
| `login_validator_test.dart` | Student graduation / enrollment error mapping |
| `chat_models_test.dart` | Chat DTO parsing |
| `chat_media_url_test.dart` | Media URL resolution |
| `chat_cache_test.dart` | Chat landing cache |
| `push_payload_crypto_test.dart` | FCM payload encryption |
| `pending_outgoing_message_test.dart` | Outgoing message queue model |
| `widget_test.dart` | App smoke |
| `e2e/*.dart` | Mock-HTTP E2E scenarios (no device) |

## Integration tests (`integration_test/`)

Device/emulator suites under `integration_test/`. Most use an in-process HTTP mock (no live API). `live_demo_e2e_test.dart` hits a real backend when `E2E_LIVE=true`.

| File | API | Covers |
|------|-----|--------|
| `login_e2e_test.dart` | Mock (validation only on device) | Login form validation, invalid credentials |
| `student_chat_e2e_test.dart` | Mock | Login → landing → tabs → room |
| `chat_room_e2e_test.dart` | Mock | Read-only channel, message list |
| `teacher_admin_chat_e2e_test.dart` | Mock | Teacher + admin portal navigation |
| `live_demo_e2e_test.dart` | **Live** | Student demo login → chat landing |

### `API_BASE_URL` (Android emulator)

The Flutter app reads the backend origin at **build/test time** via `--dart-define=API_BASE_URL=…` (`lib/config/app_config.dart`). Default: `http://10.0.2.2:5000` (Android emulator alias for the host machine).

| Target | `API_BASE_URL` |
|--------|----------------|
| Android emulator | `http://10.0.2.2:5000` |
| iOS simulator | `http://127.0.0.1:5000` |
| Physical device | `http://<your-lan-ip>:5000` |

CI sets `API_BASE_URL=http://10.0.2.2:5000` inside `reactivecircus/android-emulator-runner`. The API process binds `HOST=0.0.0.0` on port `5000` so the emulator can reach it.

### Demo seed (live E2E only)

`live_demo_e2e_test.dart` requires the **MCS-DEMO** seed:

```bash
cd backend
npm run db:reset:demo   # migrate reset + seed:demo
npm run dev             # or: npx ts-node server.ts with HOST=0.0.0.0
```

| Role | Username | Password |
|------|----------|----------|
| Student | `demo_pg_ahmed` | `DemoStudent@123` |
| Teacher | `demo_teacher_playgroup` | `DemoTeacher@123` |
| Admin | `demo_admin` | `DemoAdmin@123` |

Redis / FCM are optional for login + chat landing smoke; CI runs without them.

### Local commands

```bash
# Mock suites on a connected device/emulator (no backend):
flutter test integration_test/ -d <device_id> --concurrency=1

# Live demo (backend + demo seed required):
flutter test integration_test/live_demo_e2e_test.dart \
  --dart-define=E2E_LIVE=true \
  --dart-define=API_BASE_URL=http://10.0.2.2:5000 \
  --dart-define=E2E_API_URL=http://10.0.2.2:5000
```

## CI (`.github/workflows/test.yml`)

| Job | Trigger | What runs |
|-----|---------|-----------|
| `mobile-flutter` | PR / push | `flutter analyze`, `flutter test` (unit + `test/e2e/`) |
| `mobile-integration` | PR / push | Postgres → `prisma migrate deploy` → `seed:demo` → API on `:5000` → Android emulator → `integration_test/` |

Bootstrap scripts:

- `scripts/ci/bootstrap-mobile-integration-api.sh` — migrations, demo seed, start API, wait for `/health`
- `scripts/ci/run-mobile-integration-tests.sh` — `flutter test integration_test/` on the emulator

### CI limitations

- **Slow**: Android emulator startup + full `integration_test/` suite (~15–45 min depending on runner load).
- **x86_64 API 29 only**: matches `android-emulator-runner` config; physical ARM behavior may differ slightly.
- **Live path**: CI sets `E2E_LIVE=true` so `live_demo_e2e_test.dart` runs against the seeded API; mock suites still use `E2eHttpMock` and do not depend on network.
- **No iOS simulator** on GitHub-hosted Linux runners.
