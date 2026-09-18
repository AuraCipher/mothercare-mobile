import 'dart:io';

import '../../uploads/upload_task_store.dart';

/// Bounded garbage collection for chat staged files (M5 §30).
///
/// Scopes: `mcs_chat_cache/<uid>/chat_uploads/` (M4 tray staging) and legacy
/// `mcs_chat_cache/<uid>/pending_media/`.
///
/// Rules (all must hold for deletion):
/// - the file is NOT referenced by any non-terminal M3 upload task
///   (active uploads and unsent tray work are never touched);
/// - the file is NOT inside another user's directory (caller passes the
///   exact user dir; nothing above it is ever listed);
/// - the file is older than [maxAge] (default 7 days) — crash windows and
///   slow retries are never collected eagerly;
/// - at most [maxDeletions] files per run (bounded work on every boot).
///
/// Returns the number of files removed. Never throws.
class ChatStagingGC {
  const ChatStagingGC();

  Future<int> collect({
    required Directory userCacheDir,
    required UploadTaskStore store,
    required String userId,
    Duration maxAge = const Duration(days: 7),
    int maxDeletions = 50,
  }) async {
    try {
      return await _collect(
        userCacheDir: userCacheDir,
        store: store,
        userId: userId,
        maxAge: maxAge,
        maxDeletions: maxDeletions,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<int> _collect({
    required Directory userCacheDir,
    required UploadTaskStore store,
    required String userId,
    required Duration maxAge,
    required int maxDeletions,
  }) async {
    if (!await userCacheDir.exists()) return 0;
    final tasks = await store.listUserTasks(userId);
    // Only in-flight work pins files. Terminal rows never pin: sent tasks
    // already dropped their rows (and staged copies at send time), while
    // completed-unsent previews are expendable — sending needs only the
    // FileRecord ids, and tiles fall back to icons when the file is gone.
    final referenced = <String>{
      for (final task in tasks)
        if (!task.isTerminal) task.localPath,
    };
    final cutoff = DateTime.now().subtract(maxAge);
    var removed = 0;
    await for (final entity in userCacheDir.list(recursive: true, followLinks: false)) {
      if (removed >= maxDeletions) break;
      if (entity is! File) continue;
      if (referenced.contains(entity.path)) continue;
      DateTime modified;
      try {
        modified = await entity.lastModified();
      } catch (_) {
        continue;
      }
      if (modified.isAfter(cutoff)) continue;
      try {
        await entity.delete();
        removed += 1;
      } catch (_) {}
    }
    return removed;
  }
}
