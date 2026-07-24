/// Failure injection for the mock backend.
///
/// A mock that always succeeds makes the offline paths unreachable — you can
/// write the retry logic but you cannot demo it, and no test ever proves it
/// works. Every field here corresponds to a real failure mode the client is
/// supposed to survive.
class ChaosConfig {
  const ChaosConfig({
    this.offline = false,
    this.failureRate = 0,
    this.rejectTransfers = false,
    this.dropAfterApply = false,
    this.latency = const Duration(milliseconds: 400),
  });

  /// Nothing reaches the server. Every call throws.
  final bool offline;

  /// Probability in `[0, 1]` that a call fails transiently. Drives the "flaky
  /// network" demo where some transfers queue and some go straight through.
  final double failureRate;

  /// The server refuses transfers on a business rule — the terminal case that
  /// must never be retried.
  final bool rejectTransfers;

  /// The interesting one: the server APPLIES the transfer and then the
  /// connection dies, so the client never learns it succeeded. The client must
  /// retry (it cannot know) and the idempotency key must make that retry
  /// harmless. This is the scenario reconciliation exists for, and it is
  /// almost impossible to provoke against a real server on purpose.
  final bool dropAfterApply;

  final Duration latency;

  /// No chaos — the default the app runs with.
  static const none = ChaosConfig();

  ChaosConfig copyWith({
    bool? offline,
    double? failureRate,
    bool? rejectTransfers,
    bool? dropAfterApply,
    Duration? latency,
  }) =>
      ChaosConfig(
        offline: offline ?? this.offline,
        failureRate: failureRate ?? this.failureRate,
        rejectTransfers: rejectTransfers ?? this.rejectTransfers,
        dropAfterApply: dropAfterApply ?? this.dropAfterApply,
        latency: latency ?? this.latency,
      );
}
