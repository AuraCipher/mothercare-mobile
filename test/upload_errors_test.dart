import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/uploads/upload_errors.dart';
import 'package:mobile/features/uploads/upload_task.dart';

void main() {
  const classifier = UploadErrorClassifier();

  group('retryable transport failures', () {
    test('socket/timeout without body sent → backoff', () {
      for (final e in [
        const SocketException('reset'),
        TimeoutException('t', const Duration(seconds: 1)),
        http.ClientException('closed'),
        HttpException('boom'),
      ]) {
        final c = classifier.classify(e, bodyWasSent: false);
        expect(c.action, UploadAction.retryAfterBackoff, reason: '$e');
        expect(c.isRetryable, isTrue);
      }
    });

    test('socket/timeout AFTER body sent → reconcile first (uncertain outcome)', () {
      for (final e in [
        const SocketException('reset'),
        TimeoutException('t', const Duration(seconds: 1)),
        http.ClientException('closed'),
      ]) {
        final c = classifier.classify(e, bodyWasSent: true);
        expect(c.action, UploadAction.reconcileNow, reason: '$e');
        expect(c.isRetryable, isFalse);
      }
    });
  });

  group('HTTP status mapping', () {
    test('transient statuses retry with backoff', () {
      for (final s in [408, 429, 500, 502, 503, 504]) {
        final c = classifier.classify(
            UploadApiException('x', statusCode: s), bodyWasSent: false);
        expect(c.action, UploadAction.retryAfterBackoff, reason: '$s');
      }
    });

    test('409 reconciles; 410 expires; 404 recreates', () {
      expect(
          classifier.classify(UploadApiException('x', statusCode: 409), bodyWasSent: true)
              .action,
          UploadAction.reconcileNow);
      expect(
          classifier.classify(UploadApiException('x', statusCode: 410), bodyWasSent: true)
              .action,
          UploadAction.markExpired);
      expect(
          classifier.classify(UploadApiException('x', statusCode: 404), bodyWasSent: true)
              .action,
          UploadAction.recreateSession);
    });

    test('permanent statuses never retry', () {
      for (final s in [400, 401, 403, 411, 413, 415, 422]) {
        final c = classifier.classify(
            UploadApiException('x', statusCode: s), bodyWasSent: true);
        expect(c.action, UploadAction.failPermanent, reason: '$s');
      }
      expect(
          classifier.classify(UploadApiException('x', statusCode: 401), bodyWasSent: true)
              .kind,
          UploadErrorKind.auth);
    });

    test('Retry-After flows into the classification', () {
      final c = classifier.classify(
          UploadApiException('slow', statusCode: 429, retryAfterSeconds: 7),
          bodyWasSent: false);
      expect(c.retryAfterSeconds, 7);
      expect(c.kind, UploadErrorKind.rateLimited);
    });
  });

  group('local file failures are permanent', () {
    test('FileSystemException → fileGone, no retry', () {
      final c = classifier.classify(
          const FileSystemException('gone', '/a'), bodyWasSent: true);
      expect(c.kind, UploadErrorKind.fileGone);
      expect(c.action, UploadAction.failPermanent);
    });
  });

  group('parseRetryAfterSeconds', () {
    test('delta-seconds, HTTP date, garbage', () {
      expect(parseRetryAfterSeconds('7'), 7);
      expect(parseRetryAfterSeconds(null), isNull);
      expect(parseRetryAfterSeconds('garbage'), isNull);
      final future = HttpDate.format(DateTime.now().add(const Duration(seconds: 30)));
      expect(parseRetryAfterSeconds(future), inInclusiveRange(25, 30));
    });
  });
}
