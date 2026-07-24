import 'dart:math';

/// Failure injection, driven by environment variables so the server can be
/// started in a broken mode without editing code:
///
///     CHAOS_FAILURE_RATE=0.5 CHAOS_DROP_AFTER_APPLY=true dart run bin/server.dart
class Chaos {
  Chaos({
    this.failureRate = 0,
    this.rejectTransfers = false,
    this.dropAfterApply = false,
    this.latencyMs = 0,
    Random? random,
  }) : _random = random ?? Random();

  factory Chaos.fromEnvironment(Map<String, String> env) => Chaos(
        failureRate: double.tryParse(env['CHAOS_FAILURE_RATE'] ?? '') ?? 0,
        rejectTransfers: env['CHAOS_REJECT_TRANSFERS'] == 'true',
        dropAfterApply: env['CHAOS_DROP_AFTER_APPLY'] == 'true',
        latencyMs: int.tryParse(env['CHAOS_LATENCY_MS'] ?? '') ?? 0,
      );

  final double failureRate;
  final bool rejectTransfers;

  /// Apply the transfer, then hang up before replying. The client cannot tell
  /// this from a request that never arrived, which is exactly why the
  /// idempotency key has to make its retry harmless.
  final bool dropAfterApply;

  final int latencyMs;
  final Random _random;

  bool get shouldFail => failureRate > 0 && _random.nextDouble() < failureRate;

  Future<void> delay() => latencyMs == 0
      ? Future<void>.value()
      : Future<void>.delayed(Duration(milliseconds: latencyMs));
}
