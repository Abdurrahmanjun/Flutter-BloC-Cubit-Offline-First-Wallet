import '../entities/sync_status.dart';

/// The outbox worker, as the rest of the app sees it.
///
/// Presentation depends on this rather than on the concrete service, so the
/// UI never reaches into the data layer — and a test can drive the dashboard
/// through a hand-written stream instead of a real sync loop.
abstract class WalletSync {
  Stream<SyncStatus> get status;
  SyncStatus get current;

  /// Drain now — a manual "sync" tap, or after the app resumes.
  Future<void> sync();

  /// Retry a queue that stopped and will not restart on its own.
  Future<void> resume();

  /// Give up on a transfer that is blocking everything behind it.
  Future<void> cancelQueued(String txId);
}
