import 'dart:math';

/// Bounded exponential backoff with jitter. Pure math — unit-testable,
/// no timers inside (the engine owns scheduling).
class UploadBackoffPolicy {
  UploadBackoffPolicy({
    this.maxAttempts = 6,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.maxJitter = const Duration(milliseconds: 500),
    Random? random,
  }) : _random = random;

  /// Attempts are 1-based. Attempt 1 fails → [delayForAttempt](1).
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration maxJitter;
  final Random? _random;

  bool shouldRetry(int failedAttempts) => failedAttempts < maxAttempts;

  Duration delayForAttempt(int failedAttempt) {
    final n = failedAttempt < 1 ? 1 : failedAttempt;
    var delay = baseDelay * (1 << (n - 1));
    if (delay > maxDelay) delay = maxDelay;
    final jitterMs = _random == null ? 0 : _random.nextInt(maxJitter.inMilliseconds + 1);
    return delay + Duration(milliseconds: jitterMs);
  }
}
