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

Require a running backend + device/emulator:

| File | Covers |
|------|--------|
| `login_e2e_test.dart` | Login flow |
| `student_chat_e2e_test.dart` | Student chat landing |
| `chat_room_e2e_test.dart` | Room messaging |
| `teacher_admin_chat_e2e_test.dart` | Teacher/staff chat |
| `live_demo_e2e_test.dart` | Full demo path |

```bash
# With API running and device connected:
flutter test integration_test/login_e2e_test.dart --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

CI runs `flutter analyze` + `flutter test` (unit). Integration tests are documented here for manual/staging runs until emulator CI is added.
