import 'dart:async';
import 'dart:math';

import '../../core/error/exceptions.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/entities/tx_status.dart';
import '../../domain/repositories/wallet_sync.dart';
import '../datasources/wallet_local_datasource.dart';
import '../datasources/wallet_remote_datasource.dart';
import 'backoff_policy.dart';

/// Drains the outbox: the piece that makes "syncs when you reconnect" true.
///
/// Three rules govern the drain, and each one exists because the alternative
/// is wrong for money:
///
///  * **Strictly ordered.** Rows go out oldest-first and the drain stops at
///    the first transient failure. Skipping ahead would reorder the ledger,
///    and the server could accept a later transfer it would have declined
///    once the earlier one landed.
///  * **Backoff on the row.** Attempt counts and the next-attempt time are
///    persisted, so killing the app does not reset them.
///  * **Rejections are terminal.** A transfer the server refused is closed
///    out, never retried. Retrying it would fail identically forever while
///    blocking everything behind it.
class SyncService implements WalletSync {
  SyncService({
    required WalletLocalDataSource local,
    required WalletRemoteDataSource remote,
    Stream<bool>? onOnline,
    BackoffPolicy backoff = const BackoffPolicy(),
    DateTime Function()? clock,
    Random? random,
  })  : _local = local,
        _remote = remote,
        _onOnline = onOnline,
        _backoff = backoff,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  final WalletLocalDataSource _local;
  final WalletRemoteDataSource _remote;

  /// Emits `true` when connectivity returns. Injected as a plain bool stream
  /// rather than a `Connectivity` instance so this class stays free of plugin
  /// bindings — it is testable without a Flutter binding.
  final Stream<bool>? _onOnline;

  final BackoffPolicy _backoff;
  final DateTime Function() _clock;
  final Random _random;

  final _status = StreamController<SyncStatus>.broadcast();
  StreamSubscription<bool>? _connectivitySub;

  /// Guards against overlapping drains — connectivity, app-resume and a manual
  /// refresh can all fire at once, and two drains would push the same row
  /// twice. (Harmless thanks to idempotency, but it would double the traffic
  /// and race on the attempt counter.)
  bool _draining = false;

  /// Set when the queue needs a human. Connectivity alone will not clear it.
  bool _parked = false;

  SyncStatus _current = const SyncIdle();

  @override
  Stream<SyncStatus> get status => _status.stream;
  @override
  SyncStatus get current => _current;
  bool get isParked => _parked;

  /// Subscribes to connectivity and drains once for whatever is already
  /// queued from a previous session.
  Future<void> start() async {
    _connectivitySub =
        _onOnline?.where((online) => online).listen((_) => unawaited(sync()));
    await sync();
  }

  /// Call when the app returns to the foreground: connectivity events do not
  /// fire while backgrounded, so a resumed app can be online with a stale
  /// queue and no event coming.
  Future<void> onResumed() => sync();

  @override
  Future<void> sync() async {
    if (_draining || _parked) return;
    _draining = true;
    try {
      await _emit(const SyncInProgress());

      for (final tx in await _local.pendingTransactions()) {
        final pending = tx.status;
        if (pending is! Pending) continue;

        if (pending.attempts >= _backoff.maxAttempts) {
          // Out of retries, but "no reply" and "no delivery" look identical
          // from here. Before involving a human, ask the server whether it
          // actually has this transfer — its ledger settles the question that
          // retrying never could.
          if ((await _tryReconcile()).contains(tx.id)) continue;

          // Still unknown. Deliberately NOT reversed: the transfer may really
          // have been applied, and giving the money back would invent it.
          return _park(
            'Could not reach the server after ${pending.attempts} attempts',
            blockedTxId: tx.id,
          );
        }

        if (!pending.isDueAt(_clock())) break; // still cooling off

        try {
          final ack = await _remote.pushTransfer(
            idempotencyKey: tx.id,
            toCounterparty: tx.counterparty,
            amountCents: tx.amountCents,
          );
          await _local.confirmTransfer(
            txId: tx.id,
            confirmedBalanceCents: ack.balanceCents,
            serverTime: ack.serverTime,
          );
        } on RejectedException catch (e) {
          // Terminal, and it does not block the queue: the rows behind it are
          // independent transfers that may well succeed.
          await _local.markRejected(txId: tx.id, reason: e.message);
          continue;
        } on AuthExpiredException catch (e) {
          return _park(e.message);
        } on WalletException catch (e) {
          await _backOff(tx.id, pending, e.message);
          break; // head-of-line: order matters more than throughput
        }
      }

      await _emit(SyncIdle(queued: await _local.pendingCount()));
    } finally {
      _draining = false;
    }
  }

  /// The user's escape hatch for a transfer stuck at the head of the queue.
  /// Closing it out unblocks everything behind it.
  @override
  Future<void> cancelQueued(String txId) async {
    await _local.markRejected(txId: txId, reason: 'Cancelled');
    _parked = false;
    await sync();
  }

  /// Retry a parked queue — after re-authenticating, or when the user asks.
  ///
  /// The attempt counters are cleared too. Without that, the row that parked
  /// the queue is still at the cap and the very next drain parks again, making
  /// this a no-op. An explicit request from the user is a fresh start.
  @override
  Future<void> resume() async {
    await _local.resetRetries();
    _parked = false;
    await sync();
  }

  /// Asks the server what it actually has and folds it in. Returns the ids
  /// that turned out to be settled. A failure here is not fatal — it just
  /// means the question stays open.
  Future<Set<String>> _tryReconcile() async {
    try {
      final ledger = await _remote.fetchTransactions();
      final account = await _remote.fetchAccount();
      return await _local.reconcile(
        serverTransactions: ledger,
        account: account,
      );
    } on WalletException {
      return const {};
    }
  }

  Future<void> _backOff(String txId, Pending pending, String error) async {
    final attempts = pending.attempts + 1;
    await _local.scheduleRetry(
      txId: txId,
      attempts: attempts,
      nextAttemptAt: _clock().add(_backoff.delayFor(attempts, _random)),
      lastError: error,
    );
  }

  Future<void> _park(String reason, {String? blockedTxId}) async {
    _parked = true;
    await _emit(SyncParked(
      reason: reason,
      blockedTxId: blockedTxId,
      queued: await _local.pendingCount(),
    ));
  }

  Future<void> _emit(SyncStatus status) async {
    _current = status is SyncInProgress
        ? SyncInProgress(queued: await _local.pendingCount())
        : status;
    if (!_status.isClosed) _status.add(_current);
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    await _status.close();
  }
}
