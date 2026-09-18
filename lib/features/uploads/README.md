# M3 — Flutter Resumable Upload Engine

Client-side only. The backend M1/M2 protocol (`POST/GET/PATCH/complete/DELETE
/api/upload-sessions`) is authoritative; this engine implements the client half
and nothing else. No chat code lives here — M4 consumes completed tasks.

## Recovery contract (read this before touching the engine)

```text
SQLite offset is a cached hint.
Server bytesUploaded is the truth.
PATCH is sequential (one stream per file, 5 MiB chunks).
409 means "re-fetch the session and continue from ITS offset".
A timeout after the body was sent can mean SUCCESS — never resend blindly.
Completion is idempotent — a lost response is recovered by GET, not by
duplicating work.
Cancellation is terminal — a cancelled task never auto-resumes.
```

## Files

| File | Role |
|---|---|
| `upload_task.dart` | `UploadTask` recovery record + client state machine + transition guard + `newIdempotencyKey()` (128-bit `Random.secure`, no new dependency) |
| `upload_errors.dart` | `UploadApiException` (status + `Retry-After`), pure `UploadErrorClassifier` → `UploadAction` (`retryNow` / `retryAfterBackoff` / `reconcileNow` / `recreateSession` / `failPermanent` / `markExpired`) |
| `upload_backoff.dart` | Bounded exp-backoff + jitter (pure math, `maxAttempts: 6`) |
| `upload_session_api.dart` | Raw M1/M2 HTTP: create / GET / PATCH chunk (`Upload-Offset`, octet-stream, 90 s budget deliberately longer than the server 60 s timeout) / complete / cancel |
| `chunk_reader.dart` | Bounded `RandomAccessFile` range reads — one 5 MiB buffer at a time, never the whole file |
| `upload_task_store.dart` | sqflite CRUD on `upload_tasks` (schema v2; `(user, key)` unique for enqueue dedupe) |
| `resumable_upload_engine.dart` | Per-file driver: create → reconcile → chunk loop → complete, with cancel/recreate/expiry handling |
| `upload_scheduler.dart` | Central queue: photo lane (default 4) + video lane (default 1), reactive connectivity/lifecycle gating, `recover()` for boot/login, staggered resume |
| `upload_diagnostics.dart` | Redacted structured logging (ids/offsets/counts only — no tokens, paths, or bytes) |

## Lifecycle

`queued → creatingSession → ready → uploading ⇄ (paused | retryWait) → completing → completed`,
with `cancelling → cancelled`, `failed` (explicit `retry()` requeues, same key),
`expired` (terminal; `retry()` mints a FRESH key since the server session is gone).

## How M4 should consume this (without coupling)

1. `enqueue(userId, localPath, fileName, mimeType, purpose: 'chat'/'video'/…,
   scope: {roomId, academicYearId, …})` → `UploadTask`.
2. Listen to `scheduler.taskUpdates` (per-file progress from
   **server-acknowledged** bytes only) and `scheduler.summary` (aggregate).
3. When a task reaches `completed`, read `task.fileRecordId` / `task.fileUrl`
   and create the chat message in the chat layer. The engine never sends messages.
4. Wire app signals: `handleConnectivityLost/Restored`,
   `handleAppPaused/Resumed` (e.g. from a `WidgetsBindingObserver`),
   `recover(userId)` at startup/login, token via `UploadTokenProvider`
   (e.g. `SessionStorage.getToken`).

## Deliberate non-goals

No `connectivity_plus` (connectivity is a reactive hint from real HTTP
outcomes — an "online" flag never proves reachability); no background-upload
framework (interruption is always recoverable via persisted state + server
truth, which is the actual requirement); no client-side media policy beyond
what the backend enforces (no invented duration/size caps).
