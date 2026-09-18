import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/api/api_exception.dart';
import 'upload_task.dart';

/// What the driver should do next. Decided by pure, unit-testable rules.
enum UploadAction {
  /// Safe to send immediately (idempotent read or fresh chunk at known offset).
  retryNow,
  /// Wait for backoff, then reconcile-from-server before continuing.
  retryAfterBackoff,
  /// Stop and GET the session NOW: the outcome is uncertain or conflicting.
  reconcileNow,
  /// Session is gone server-side: POST create with the SAME idempotency key.
  recreateSession,
  /// Terminal local failure. No automatic retry.
  failPermanent,
  /// Terminal expiry. A manual retry needs a fresh idempotency key.
  markExpired,
}

/// HTTP failure from the upload API carrying status + Retry-After.
/// Extends the project's [ApiException] so existing catch sites keep working.
class UploadApiException extends ApiException {
  UploadApiException(super.message, {super.statusCode, this.retryAfterSeconds});

  final int? retryAfterSeconds;
}

class ClassifiedUploadError {
  const ClassifiedUploadError({
    required this.kind,
    required this.action,
    required this.message,
    this.retryAfterSeconds,
  });

  final UploadErrorKind kind;
  final UploadAction action;
  final String message;
  final int? retryAfterSeconds;

  bool get isRetryable =>
      action == UploadAction.retryNow || action == UploadAction.retryAfterBackoff;
}

/// Central, testable error classification.
///
/// [bodyWasSent] distinguishes "definitely failed before the server could
/// act" (safe immediate retry) from "the server may already have committed"
/// (must reconcile first). For PATCH chunks the body is always in flight,
/// so chunk timeouts/connection errors ALWAYS reconcile first.
class UploadErrorClassifier {
  const UploadErrorClassifier();

  ClassifiedUploadError classify(Object error, {required bool bodyWasSent}) {
    if (error is UploadApiException && error.statusCode != null) {
      return _byStatus(error.statusCode!, error.message,
          retryAfterSeconds: error.retryAfterSeconds);
    }
    if (error is ApiException && error.statusCode != null) {
      return _byStatus(error.statusCode!, error.message);
    }
    if (error is TimeoutException) {
      return bodyWasSent
          ? const ClassifiedUploadError(
              kind: UploadErrorKind.timeout,
              action: UploadAction.reconcileNow,
              message: 'Request timed out after the request was sent; reconciling.',
            )
          : const ClassifiedUploadError(
              kind: UploadErrorKind.timeout,
              action: UploadAction.retryAfterBackoff,
              message: 'Request timed out.',
            );
    }
    if (error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TlsException ||
        error is http.ClientException) {
      return bodyWasSent
          ? const ClassifiedUploadError(
              kind: UploadErrorKind.network,
              action: UploadAction.reconcileNow,
              message: 'Connection lost after the request was sent; reconciling.',
            )
          : const ClassifiedUploadError(
              kind: UploadErrorKind.network,
              action: UploadAction.retryAfterBackoff,
              message: 'Connection failed.',
            );
    }
    if (error is FileSystemException) {
      return ClassifiedUploadError(
        kind: UploadErrorKind.fileGone,
        action: UploadAction.failPermanent,
        message: 'Local file is no longer readable: ${error.message}',
      );
    }
    if (error is StateError && error.message.contains('Upload session is')) {
      // Defensive: should not happen; treat as reconcile, not crash-loop.
      return const ClassifiedUploadError(
        kind: UploadErrorKind.conflict,
        action: UploadAction.reconcileNow,
        message: 'Internal state conflict; reconciling with server.',
      );
    }
    return ClassifiedUploadError(
      kind: UploadErrorKind.network,
      action: bodyWasSent ? UploadAction.reconcileNow : UploadAction.retryAfterBackoff,
      message: 'Unexpected error: $error',
    );
  }

  ClassifiedUploadError _byStatus(int status, String message, {int? retryAfterSeconds}) {
    switch (status) {
      case 401:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.auth, action: UploadAction.failPermanent,
          message: 'Not signed in. Please sign in again.');
      case 403:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.forbidden, action: UploadAction.failPermanent,
          message: 'Not allowed to upload here.');
      case 404:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.notFound, action: UploadAction.recreateSession,
          message: 'Upload session not found on server.');
      case 408:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.timeout, action: UploadAction.retryAfterBackoff,
          message: 'Request timeout.');
      case 409:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.conflict, action: UploadAction.reconcileNow,
          message: 'Offset conflict; reconciling with server offset.');
      case 410:
        return const ClassifiedUploadError(
          kind: UploadErrorKind.gone, action: UploadAction.markExpired,
          message: 'Upload session expired.');
      case 411:
      case 400:
      case 413:
      case 415:
      case 422:
        return ClassifiedUploadError(
          kind: UploadErrorKind.validation, action: UploadAction.failPermanent,
          message: message);
      case 429:
        return ClassifiedUploadError(
          kind: UploadErrorKind.rateLimited, action: UploadAction.retryAfterBackoff,
          message: 'Too many requests; backing off.', retryAfterSeconds: retryAfterSeconds);
      case 500:
      case 502:
      case 503:
      case 504:
        return ClassifiedUploadError(
          kind: UploadErrorKind.server, action: UploadAction.retryAfterBackoff,
          message: 'Server error ($status); backing off.', retryAfterSeconds: retryAfterSeconds);
      default:
        return ClassifiedUploadError(
          kind: UploadErrorKind.server, action: UploadAction.failPermanent,
          message: message);
    }
  }
}

/// Parses `Retry-After` (delta-seconds or HTTP date) into seconds.
int? parseRetryAfterSeconds(String? header) {
  if (header == null || header.isEmpty) return null;
  final seconds = int.tryParse(header.trim());
  if (seconds != null) return seconds < 0 ? 0 : seconds;
  try {
    final date = HttpDate.parse(header);
    final diff = date.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  } catch (_) {
    return null;
  }
}
