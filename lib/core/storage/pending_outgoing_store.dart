import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/chat/models/pending_outgoing_message.dart';

class PendingOutgoingStore {
  PendingOutgoingStore._();

  static final PendingOutgoingStore instance = PendingOutgoingStore._();

  Directory? _baseDir;

  Future<Directory> _pendingMediaDir(String userId) async {
    _baseDir ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId, 'pending_media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _pendingFile(String userId, String roomId) async {
    _baseDir ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId, 'pending'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeRoom = roomId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(p.join(dir.path, '$safeRoom.json'));
  }

  /// Copies [source] into app storage so uploads survive temp directory cleanup.
  Future<String?> persistMediaFile({
    required String userId,
    required String localId,
    required File source,
  }) async {
    try {
      if (!await source.exists()) return null;
      final dir = await _pendingMediaDir(userId);
      final ext = p.extension(source.path);
      final dest = File(p.join(dir.path, '$localId$ext'));
      await source.copy(dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  Future<List<PendingOutgoingMessage>> loadRoom({
    required String userId,
    required String roomId,
  }) async {
    try {
      final file = await _pendingFile(userId, roomId);
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      return list
          .map((e) => PendingOutgoingMessage.fromJson(e as Map<String, dynamic>))
          .where((item) => item.localId.isNotEmpty)
          .map(_normalizeRestored)
          .toList();
    } catch (_) {
      return [];
    }
  }

  PendingOutgoingMessage _normalizeRestored(PendingOutgoingMessage item) {
    if (item.phase == PendingSendPhase.failed) return item;
    return item.copyWith(phase: PendingSendPhase.failed, progress: 0);
  }

  Future<void> saveRoom({
    required String userId,
    required String roomId,
    required List<PendingOutgoingMessage> pending,
  }) async {
    try {
      final file = await _pendingFile(userId, roomId);
      final keep = pending
          .where((p) => p.phase != PendingSendPhase.sending)
          .toList();
      if (keep.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(jsonEncode(keep.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clearUser(String userId) async {
    try {
      _baseDir ??= await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(_baseDir!.path, 'mcs_chat_cache', userId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
