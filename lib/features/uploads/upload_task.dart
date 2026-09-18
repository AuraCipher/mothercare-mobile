import 'dart:convert';
import 'dart:math';

/// Client-side lifecycle of one resumable file upload.
///
/// This is a RECOVERY/QUEUE record, not a copy of the backend session:
/// the server's `bytesUploaded` is authoritative; [serverBytes] here is only
/// ever written from server acknowledgements or session GETs.
enum UploadTaskState {
  queued,
  creatingSession,
  ready,
  uploading,
  paused,
  retryWait,
  completing,
  completed,
  cancelling,
  cancelled,
  failed,
  expired,
}

/// Terminal states: the driver never leaves them automatically.
/// `failed` is terminal for the driver but the USER may retry it explicitly
/// (same idempotency key); `expired` needs a fresh key (see engine).
const _terminalStates = {
  UploadTaskState.completed,
  UploadTaskState.cancelled,
  UploadTaskState.failed,
  UploadTaskState.expired,
};

bool isUploadTerminal(UploadTaskState state) => _terminalStates.contains(state);

/// Allowed transitions. Anything else is a programming error and throws.
const _allowedTransitions = <UploadTaskState, Set<UploadTaskState>>{
  // Note: several active states include `completed` — completion is
  // *discoverable* via server adopt (another path may have finished the
  // upload); it is never fabricated locally. Terminal-to-completed stays
  // forbidden.
  UploadTaskState.queued: {
    UploadTaskState.creatingSession,
    UploadTaskState.ready,
    UploadTaskState.uploading,
    UploadTaskState.retryWait,
    UploadTaskState.completed,
    UploadTaskState.paused,
    UploadTaskState.failed,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.creatingSession: {
    UploadTaskState.ready,
    UploadTaskState.uploading,
    UploadTaskState.completed,
    UploadTaskState.retryWait,
    UploadTaskState.paused,
    UploadTaskState.queued,
    UploadTaskState.failed,
    UploadTaskState.expired,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.ready: {
    UploadTaskState.uploading,
    UploadTaskState.completing,
    UploadTaskState.completed,
    UploadTaskState.paused,
    UploadTaskState.queued,
    UploadTaskState.retryWait,
    UploadTaskState.failed,
    UploadTaskState.expired,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.uploading: {
    UploadTaskState.uploading,
    UploadTaskState.ready,
    UploadTaskState.queued,
    UploadTaskState.completing,
    UploadTaskState.completed,
    UploadTaskState.paused,
    UploadTaskState.retryWait,
    UploadTaskState.failed,
    UploadTaskState.expired,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.paused: {
    UploadTaskState.queued,
    UploadTaskState.retryWait,
    UploadTaskState.completed,
    UploadTaskState.failed,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.retryWait: {
    UploadTaskState.queued,
    UploadTaskState.uploading,
    UploadTaskState.completed,
    UploadTaskState.paused,
    UploadTaskState.failed,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.completing: {
    UploadTaskState.completed,
    UploadTaskState.ready,
    UploadTaskState.retryWait,
    UploadTaskState.failed,
    UploadTaskState.expired,
    UploadTaskState.cancelling,
    UploadTaskState.cancelled,
  },
  UploadTaskState.completed: {},
  UploadTaskState.cancelling: {UploadTaskState.cancelled, UploadTaskState.failed},
  UploadTaskState.cancelled: {},
  UploadTaskState.failed: {UploadTaskState.queued},
  UploadTaskState.expired: {},
};

void assertUploadTransition(UploadTaskState from, UploadTaskState to) {
  if (!(_allowedTransitions[from]?.contains(to) ?? false)) {
    throw StateError('Invalid upload transition $from -> $to');
  }
}

/// Coarse, testable error category for retry/reconcile decisions.
enum UploadErrorKind {
  none,
  network,
  timeout,
  rateLimited,
  server,
  conflict,
  auth,
  forbidden,
  notFound,
  gone,
  validation,
  fileGone,
  cancelled,
}

/// Generates a stable 128-bit client idempotency key (32 hex chars) using a
/// cryptographically secure RNG. One key per LOGICAL upload: retries reuse it.
String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class UploadTask {
  UploadTask({
    required this.taskId,
    required this.userId,
    required this.idempotencyKey,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    required this.purpose,
    required this.expectedSize,
    this.sessionId,
    this.serverBytes = 0,
    this.state = UploadTaskState.queued,
    this.retryCount = 0,
    this.errorKind = UploadErrorKind.none,
    this.errorMessage,
    this.fileRecordId,
    this.fileUrl,
    this.cancelRequested = false,
    this.nextRetryAt,
    this.scopeJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String taskId;
  final String userId;
  final String idempotencyKey;
  final String localPath;
  final String fileName;
  final String mimeType;
  final String purpose;
  final int expectedSize;
  final String? sessionId;
  final int serverBytes;
  final UploadTaskState state;
  final int retryCount;
  final UploadErrorKind errorKind;
  final String? errorMessage;
  final String? fileRecordId;
  final String? fileUrl;
  final bool cancelRequested;
  final DateTime? nextRetryAt;
  /// Opaque create-scope for later stages (entityType/entityId/roomId/
  /// academicYearId/metadata). Passed through to session creation only.
  final String? scopeJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Decoded [scopeJson] or empty when absent/invalid.
  Map<String, dynamic> get scope {
    if (scopeJson == null || scopeJson!.isEmpty) return {};
    try {
      final decoded = jsonDecode(scopeJson!);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  /// 0.0–1.0 from SERVER-acknowledged bytes only. Never optimistic.
  double get progress => expectedSize <= 0 ? 0 : (serverBytes / expectedSize).clamp(0.0, 1.0);

  bool get isVideo => purpose == 'video';

  bool get isTerminal => isUploadTerminal(state);

  UploadTask copyWith({
    String? sessionId,
    int? serverBytes,
    UploadTaskState? state,
    int? retryCount,
    UploadErrorKind? errorKind,
    String? errorMessage,
    bool clearError = false,
    String? fileRecordId,
    String? fileUrl,
    bool? cancelRequested,
    DateTime? nextRetryAt,
    bool clearNextRetry = false,
    String? scopeJson,
  }) {
    if (state != null) assertUploadTransition(this.state, state);
    return UploadTask(
      taskId: taskId,
      userId: userId,
      idempotencyKey: idempotencyKey,
      localPath: localPath,
      fileName: fileName,
      mimeType: mimeType,
      purpose: purpose,
      expectedSize: expectedSize,
      sessionId: sessionId ?? this.sessionId,
      serverBytes: serverBytes ?? this.serverBytes,
      state: state ?? this.state,
      retryCount: retryCount ?? this.retryCount,
      errorKind: clearError ? UploadErrorKind.none : (errorKind ?? this.errorKind),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fileRecordId: fileRecordId ?? this.fileRecordId,
      fileUrl: fileUrl ?? this.fileUrl,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      nextRetryAt: clearNextRetry ? null : (nextRetryAt ?? this.nextRetryAt),
      scopeJson: scopeJson ?? this.scopeJson,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'userId': userId,
        'idempotencyKey': idempotencyKey,
        'sessionId': sessionId,
        'localPath': localPath,
        'fileName': fileName,
        'mimeType': mimeType,
        'purpose': purpose,
        'expectedSize': expectedSize,
        'serverBytes': serverBytes,
        'state': state.name,
        'retryCount': retryCount,
        'errorKind': errorKind.name,
        'errorMessage': errorMessage,
        'fileRecordId': fileRecordId,
        'fileUrl': fileUrl,
        'cancelRequested': cancelRequested ? 1 : 0,
        'nextRetryAt': nextRetryAt?.millisecondsSinceEpoch,
        'scopeJson': scopeJson,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  static UploadTask fromJson(Map<String, dynamic> json) => UploadTask(
        taskId: json['taskId'] as String,
        userId: json['userId'] as String,
        idempotencyKey: json['idempotencyKey'] as String,
        sessionId: json['sessionId'] as String?,
        localPath: json['localPath'] as String,
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        purpose: (json['purpose'] as String?) ?? 'document',
        expectedSize: json['expectedSize'] as int,
        serverBytes: (json['serverBytes'] as int?) ?? 0,
        state: UploadTaskState.values.byName(json['state'] as String),
        retryCount: (json['retryCount'] as int?) ?? 0,
        errorKind: UploadErrorKind.values.byName((json['errorKind'] as String?) ?? 'none'),
        errorMessage: json['errorMessage'] as String?,
        fileRecordId: json['fileRecordId'] as String?,
        fileUrl: json['fileUrl'] as String?,
        cancelRequested: (json['cancelRequested'] as int? ?? 0) == 1,
        scopeJson: json['scopeJson'] as String?,
        nextRetryAt: (json['nextRetryAt'] as int?) != null
            ? DateTime.fromMillisecondsSinceEpoch(json['nextRetryAt'] as int)
            : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );
}
