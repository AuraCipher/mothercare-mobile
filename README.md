# Mother Care — Flutter Mobile

Phase 0: login with client-side validation, secure session storage, role routing.

## Run (development)

### 1. Start backend

```bash
cd backend
cp .env.example .env   # first time only — edit DATABASE_URL + JWT_SECRET
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
flutter run --dart-define=API_BASE_URL=http://YOUR_LAN_IP:5000
```

Find LAN IP: `hostname -I | awk '{print $1}'`

## Test logins (from seed)

| Role | Username | Password |
|------|----------|----------|
| Student | `student_ahmed` | `Student@123` |
| Student | `student_sara` | `Student@123` |
| Teacher | `fatima_teacher` | `Fatima@123` |
| Teacher | `usman_teacher` | `Usman@123` |

Admin/CEO accounts exist for **web only** — mobile shows “Web admin only”.

There is **no sign-up** in the app. All accounts are created in admin or by `prisma/seed.ts`.

## Client validation (before API)

- Identifier: required, 2–100 chars, must look like username, email, or phone
- Password: required, 6–128 chars

## Tests

```bash
cd mobile
flutter test
```
