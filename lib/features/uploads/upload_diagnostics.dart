import 'package:flutter/foundation.dart';

import 'upload_task.dart';

/// Structured, redacted client-side upload diagnostics.
///
/// Logged: task/session ids (opaque), state transitions, chunk numbers,
/// offsets, byte counts, retry counts, error categories.
/// NEVER logged: auth tokens, file contents, full local paths (basename
/// only), storage keys, R2/provider material (the client never sees any).
class UploadDiagnostic {
  UploadDiagnostic({
    required this.event,
    required this.taskId,
    this.sessionId,
    this.fromState,
    this.toState,
    this.offset,
    this.bytes,
    this.chunkNumber,
    this.attempt,
    this.errorKind,
    this.message,
  }) : at = DateTime.now();

  final DateTime at;
  final String event;
  final String taskId;
  final String? sessionId;
  final UploadTaskState? fromState;
  final UploadTaskState? toState;
  final int? offset;
  final int? bytes;
  final int? chunkNumber;
  final int? attempt;
  final UploadErrorKind? errorKind;
  final String? message;

  @override
  String toString() {
    final parts = <String>['upload.$event', 'task=$taskId'];
    if (sessionId != null) parts.add('session=$sessionId');
    if (fromState != null || toState != null) {
      parts.add('${fromState?.name ?? '?'}->${toState?.name ?? '?'}');
    }
    if (offset != null) parts.add('offset=$offset');
    if (bytes != null) parts.add('bytes=$bytes');
    if (chunkNumber != null) parts.add('chunk=$chunkNumber');
    if (attempt != null) parts.add('attempt=$attempt');
    if (errorKind != null) parts.add('error=${errorKind!.name}');
    if (message != null) parts.add(message!);
    return parts.join(' ');
  }
}

/// basename-only: full device paths can leak PII (usernames, albums).
String redactPath(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

class UploadLogger {
  UploadLogger({void Function(UploadDiagnostic)? sink, bool enabled = kDebugMode})
      : _sink = sink,
        _enabled = enabled;

  final void Function(UploadDiagnostic)? _sink;
  final bool _enabled;

  void log(UploadDiagnostic event) {
    if (!_enabled) return;
    if (_sink != null) {
      _sink(event);
      return;
    }
    debugPrint(event.toString());
  }
}
