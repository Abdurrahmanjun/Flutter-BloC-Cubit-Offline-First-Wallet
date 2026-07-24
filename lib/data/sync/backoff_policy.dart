import 'dart:math';

/// Exponential backoff with **full jitter**.
///
/// The jitter is not decoration. Without it, every device that lost the same
/// carrier retries at the same millisecond when service returns, and the
/// backend gets a self-inflicted thundering herd from its own clients. Spread
/// the retries uniformly across the window instead:
///
///     delay = random(0, min(cap, base * 2^attempts))
class BackoffPolicy {
  const BackoffPolicy({
    this.base = const Duration(seconds: 2),
    this.cap = const Duration(minutes: 5),
    this.maxAttempts = 8,
  });

  final Duration base;
  final Duration cap;

  /// After this many failures a transfer stops being retried automatically.
  /// It is NOT reversed — see the note on parking in `SyncService`.
  final int maxAttempts;

  Duration delayFor(int attempts, Random random) {
    // 2^attempts overflows nothing at these sizes, but the cap is applied
    // before jitter so the window itself never runs away.
    final exponential = base.inMilliseconds * pow(2, attempts).toInt();
    final window = min(exponential, cap.inMilliseconds);
    return Duration(milliseconds: random.nextInt(window + 1));
  }
}
