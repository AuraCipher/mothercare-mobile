# Mother Care — Flutter Mobile

Phase 0+: login, chat, read-only portal panels. API URL is set at **compile time** via `--dart-define`.

## Run (development)

### 1. Start backend

```bash
cd backend
cp .env.example .env   # first time only — edit DATABASE_URL + JWT_SECRET
# Physical phone on Wi‑Fi: HOST=0.0.0.0 in .env
npm run dev
```

Health check: `http://127.0.0.1:5000/health`

### 2. Seed test users (no sign-up in app)

```bash
cd backend
npx prisma migrate deploy
npx ts-node prisma/seed.ts
```

### 3. Run Flutter

**Android emulator** (API → host machine):

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

**iOS simulator:**

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

**Physical phone** (same Wi‑Fi as PC):

```bash
# 1. backend/.env → HOST=0.0.0.0, then restart: npm run dev
# 2. LAN IP: hostname -I | awk '{print $1}'
flutter run --dart-define=API_BASE_URL=http://YOUR_LAN_IP:5000
```

If login fails with "Cannot reach server": `HOST=0.0.0.0`, firewall port 5000, same Wi‑Fi.

## Android build notes

On a **clean** rebuild (`flutter clean` then `flutter run`), you may see two javac lines:

```
Note: Some input files use or override a deprecated API.
Note: Recompile with -Xlint:deprecation for details.
```

These come from the **`firebase_messaging`** Android plugin (Google’s Java code), not from Mother Care app code. They are **harmless** and do not affect the APK. Incremental builds usually skip them.

The Gradle “Deprecated Gradle features” banner is suppressed via `android/gradle.properties`.

## Production build (hosted backend)

The app has **no runtime `.env`**. `API_BASE_URL` is compiled into the binary when you build.

### 1. Create production defines (do not commit secrets)

```bash
cd mobile
cp dart_defines/production.example.json dart_defines/production.json
```

Edit `dart_defines/production.json`:

```json
{
  "API_BASE_URL": "https://api.your-school-domain.com",
  "PUSH_ENABLED": "true",
  "FIREBASE_API_KEY": "...",
  "FIREBASE_APP_ID": "...",
  "FIREBASE_MESSAGING_SENDER_ID": "...",
  "FIREBASE_PROJECT_ID": "..."
}
```

- Use **`https://`** for production (not `http://`).
- `PUSH_ENABLED` + Firebase keys only when FCM is configured on the backend.
- Add `dart_defines/production.json` to `.gitignore` if it contains real keys.

### 2. Build release

**Play Store (recommended — AAB):**

```bash
flutter build appbundle --release --dart-define-from-file=dart_defines/production.json
```

Output: `build/app/outputs/bundle/release/app-release.aab`

**APK (direct install / testing):**

```bash
flutter build apk --release --dart-define-from-file=dart_defines/production.json
```

**Helper script:**

```bash
chmod +x scripts/build-release.sh
./scripts/build-release.sh dart_defines/production.json
```

### 3. Signing (before Play Store)

Release builds currently use the debug keystore (fine for testing). For Play Store:

1. Create a upload keystore (`keytool -genkey ...`).
2. Add `android/key.properties` + configure `signingConfigs` in `android/app/build.gradle.kts`.
3. See [Flutter Android deployment](https://docs.flutter.dev/deployment/android).

### 4. Backend requirements for production

| Item | Notes |
|------|--------|
| Public HTTPS API | e.g. `https://api.school.com` behind nginx/Caddy |
| CORS | Not required for native mobile HTTP client |
| Socket.IO | Same origin as `API_BASE_URL`; WSS if API is HTTPS |
| Uploads/media | `API_BASE_URL` + `/api/uploads/...` must be reachable from phones |
| FCM | Backend `FCM_ENABLED=true` + Firebase service account; mobile `PUSH_ENABLED=true` |

### 5. One-off build without a JSON file

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.your-school-domain.com \
  --dart-define=PUSH_ENABLED=true
```

Each environment (staging vs prod) = separate build with different `--dart-define` values.

## Test logins (from seed)

| Role | Username | Password |
|------|----------|----------|
| Student | `student_ahmed` | `Student@123` |
| Student | `student_sara` | `Student@123` |
| Teacher | `fatima_teacher` | `Fatima@123` |
| Teacher | `usman_teacher` | `Usman@123` |

Admin/CEO accounts are **web only** — mobile shows “Web admin only”.

There is **no sign-up** in the app. Accounts come from admin or `prisma/seed.ts`.

## Tests

```bash
cd mobile
flutter test
```
