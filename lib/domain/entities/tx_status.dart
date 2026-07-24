import 'package:equatable/equatable.dart';

/// Where a transfer stands with the server.
///
/// This replaced a `synced` bool, which could not tell two very different
/// situations apart:
///
///  * [Pending]  — the server has not seen it. The money WILL move. Wait.
///  * [Rejected] — the server saw it and said no. The money will NOT move,
///                 and the local balance already reflects a debit that has to
///                 be given back.
///
/// A bool collapses those into "not synced", so the only honest response is to
/// retry forever — including the transfers that can never succeed.
///
/// Sealed so every consumer must handle all three; a new state becomes a
/// compile error at each switch rather than a silently missing branch.
sealed class TxStatus extends Equatable {
  const TxStatus();
}

/// Queued in the outbox. [attempts] and [nextAttemptAt] carry the backoff, and
/// they live on the row rather than in the worker's memory — otherwise every
/// cold start would reset the backoff and hammer the server on each launch.
class Pending extends TxStatus {
  const Pending({this.attempts = 0, this.nextAttemptAt});

  final int attempts;

  /// Null means eligible right now.
  final DateTime? nextAttemptAt;

  bool isDueAt(DateTime now) =>
      nextAttemptAt == null || !nextAttemptAt!.isAfter(now);

  Pending backedOff(DateTime nextAttempt) =>
      Pending(attempts: attempts + 1, nextAttemptAt: nextAttempt);

  @override
  List<Object?> get props => [attempts, nextAttemptAt];
}

/// The server confirmed it. [serverTime] is the server's own stamp, preferred
/// over the device's for display — device clocks drift and can be set by hand.
class Synced extends TxStatus {
  const Synced({this.serverTime});

  final DateTime? serverTime;

  @override
  List<Object?> get props => [serverTime];
}

/// A business rule refused it. Terminal: retrying produces the same answer
/// forever, so the transfer must be reversed instead.
class Rejected extends TxStatus {
  const Rejected(this.reason);

  final String reason;

  @override
  List<Object?> get props => [reason];
}
