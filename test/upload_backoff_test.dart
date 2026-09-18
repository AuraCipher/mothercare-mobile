import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/upload_backoff.dart';

void main() {
  test('exponential growth with cap', () {
    final policy = UploadBackoffPolicy(
      baseDelay: const Duration(seconds: 1),
      maxDelay: const Duration(seconds: 60),
      maxAttempts: 6,
      random: Random(42),
    );
    expect(policy.delayForAttempt(1) >= const Duration(seconds: 1), isTrue);
    expect(policy.delayForAttempt(1) <= const Duration(milliseconds: 1500), isTrue);
    expect(policy.delayForAttempt(2) >= const Duration(seconds: 2), isTrue);
    expect(policy.delayForAttempt(3) >= const Duration(seconds: 4), isTrue);
    expect(policy.delayForAttempt(10) <= const Duration(seconds: 61), isTrue);
  });

  test('budget enforced', () {
    final policy = UploadBackoffPolicy(maxAttempts: 3);
    expect(policy.shouldRetry(1), isTrue);
    expect(policy.shouldRetry(2), isTrue);
    expect(policy.shouldRetry(3), isFalse);
    expect(policy.shouldRetry(99), isFalse);
  });

  test('jitter varies delays with a seeded RNG', () {
    final seeded = UploadBackoffPolicy(baseDelay: const Duration(seconds: 1), random: Random(7));
    final unseeded = UploadBackoffPolicy(baseDelay: const Duration(seconds: 1));
    expect(seeded.delayForAttempt(1) >= const Duration(seconds: 1), isTrue);
    expect(unseeded.delayForAttempt(1), const Duration(seconds: 1));
  });
}
