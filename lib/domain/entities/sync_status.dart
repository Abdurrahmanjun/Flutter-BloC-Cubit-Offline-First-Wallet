import 'package:equatable/equatable.dart';

/// What the outbox worker is doing, for the UI to subscribe to.
sealed class SyncStatus extends Equatable {
  const SyncStatus({required this.queued});

  /// Transfers still waiting to reach the server.
  final int queued;

  @override
  List<Object?> get props => [queued];
}

/// Nothing in flight. [queued] > 0 means rows are waiting on their backoff.
class SyncIdle extends SyncStatus {
  const SyncIdle({super.queued = 0});
}

/// Draining the outbox right now.
class SyncInProgress extends SyncStatus {
  const SyncInProgress({super.queued = 0});
}

/// The queue has stopped and will not restart on its own.
///
/// Reached when a transfer exhausts its retries, or when credentials expire.
/// Because the drain is strictly ordered, everything behind the blocking
/// transfer waits too — that is deliberate. Skipping ahead would reorder the
/// ledger, and the server could accept a later transfer it would have declined
/// after the earlier one landed.
class SyncParked extends SyncStatus {
  const SyncParked({
    required this.reason,
    this.blockedTxId,
    super.queued = 0,
  });

  final String reason;

  /// The transfer holding up the queue, if one specific row is to blame.
  final String? blockedTxId;

  @override
  List<Object?> get props => [queued, reason, blockedTxId];
}
