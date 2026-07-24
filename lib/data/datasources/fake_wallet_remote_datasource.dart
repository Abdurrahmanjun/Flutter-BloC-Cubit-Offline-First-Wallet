import 'dart:math';

import '../../core/error/exceptions.dart';
import '../models/account_model.dart';
import '../models/remote_transaction.dart';
import '../models/transfer_ack.dart';
import 'chaos_config.dart';
import 'wallet_remote_datasource.dart';

/// In-process fake backend, behaviourally identical to the real one.
///
/// This is what the unit and bloc suites run against: deterministic, no
/// network, and able to produce failures a real server will not reproduce on
/// demand — above all the ambiguous timeout, where the transfer is applied and
/// the reply is lost.
///
/// It holds state rather than returning constants, because two client
/// guarantees depend on the server actually behaving like one:
///
///  * the balance must drop when a transfer is applied, or a confirmed
///    transfer would make the money visibly bounce back up;
///  * a replayed idempotency key must return the original outcome, or a retry
///    after an ambiguous timeout would double-spend.
class FakeWalletRemoteDataSource implements WalletRemoteDataSource {
  FakeWalletRemoteDataSource({
    int initialBalanceCents = 250000,
    this.chaos = ChaosConfig.none,
    Random? random,
  })  : _balanceCents = initialBalanceCents,
        _random = random ?? Random();

  int _balanceCents;
  final Random _random;

  /// Mutable so a demo screen (or a test) can flip the network mid-session.
  ChaosConfig chaos;

  /// Idempotency keys already applied, with the outcome each produced. The
  /// contract says a replay returns that same outcome rather than an error.
  final Map<String, TransferAck> _applied = {};

  /// The server's own ledger, in the order it applied things.
  final List<RemoteTransaction> _ledger = [];

  int get balanceCents => _balanceCents;

  @override
  Future<AccountModel> fetchAccount() async {
    await _transit();
    return AccountModel(
      id: 'acc_demo',
      holderName: 'Abdurrahman J. M.',
      confirmedBalanceCents: _balanceCents,
      currency: 'USD',
    );
  }

  @override
  Future<List<RemoteTransaction>> fetchTransactions() async {
    await _transit();
    return List.unmodifiable(_ledger);
  }

  @override
  Future<TransferAck> pushTransfer({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  }) async {
    await _transit();

    // 200: already applied. Same answer, no second debit.
    final seen = _applied[idempotencyKey];
    if (seen != null) return seen;

    // 422: terminal. Checked before applying, so nothing is left half-done.
    if (chaos.rejectTransfers || amountCents > _balanceCents) {
      throw const RejectedException('INSUFFICIENT_FUNDS');
    }

    _balanceCents -= amountCents;
    final ack = TransferAck(
      id: idempotencyKey,
      balanceCents: _balanceCents,
      serverTime: DateTime.now(),
    );
    _applied[idempotencyKey] = ack;
    _ledger.add(RemoteTransaction(
      id: idempotencyKey,
      counterparty: toCounterparty,
      amountCents: amountCents,
      serverTime: ack.serverTime,
    ));

    // The ambiguous timeout: applied above, but the client never finds out.
    // Its only safe move is to retry, and the replay branch above is what
    // makes that harmless.
    if (chaos.dropAfterApply) {
      throw const NetworkException('Connection lost after the request was sent');
    }

    return ack;
  }

  /// Latency plus whatever the network decides to do to this call.
  Future<void> _transit() async {
    await Future<void>.delayed(chaos.latency);
    if (chaos.offline) throw const NetworkException();
    if (chaos.failureRate > 0 && _random.nextDouble() < chaos.failureRate) {
      throw const NetworkException('Transient failure');
    }
  }
}
