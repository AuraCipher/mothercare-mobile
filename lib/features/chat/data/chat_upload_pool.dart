import '../../uploads/upload_scheduler.dart';
import '../../uploads/upload_session_api.dart';
import '../../uploads/upload_task_store.dart';
import '../../uploads/resumable_upload_engine.dart' show UploadTokenProvider;

/// Per-user UploadScheduler singletons for chat.
///
/// Rationale: uploads must survive chat-room navigation (the scheduler owns
/// in-flight drivers), but must never leak across users. Schedulers are
/// keyed by userId; [releaseAll] is called on every logout path and drops +
/// disposes them. The M3 task rows themselves are user-scoped in SQLite and
/// wiped by the existing clearUser flow.
class ChatUploadPool {
  static final Map<String, UploadScheduler> _schedulers = {};

  static UploadScheduler acquire({
    required String userId,
    required UploadTokenProvider getToken,
    String? baseUrl,
  }) {
    return _schedulers.putIfAbsent(
      userId,
      () => UploadScheduler(
        api: UploadSessionApi(baseUrl: baseUrl),
        store: UploadTaskStore(),
        getToken: getToken,
      ),
    );
  }

  static Future<void> releaseAll() async {
    final all = _schedulers.values.toList();
    _schedulers.clear();
    for (final scheduler in all) {
      try {
        await scheduler.dispose();
      } catch (_) {}
    }
  }

  static bool get isEmpty => _schedulers.isEmpty;
}
