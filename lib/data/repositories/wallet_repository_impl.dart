import 'package:dartz/dartz.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/account_view.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/tx_status.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../datasources/wallet_local_datasource.dart';
import '../datasources/wallet_remote_datasource.dart';
import '../models/transaction_model.dart';

class WalletRepositoryImpl implements WalletRepository {
  WalletRepositoryImpl({
    required this.local,
    required this.remote,
    this.uuid,
  });

  final WalletLocalDataSource local;
  final WalletRemoteDataSource remote;
  final String Function()? uuid;

  /// Client-generated, and deliberately so: this id doubles as the server's
  /// idempotency key, so a retry after an ambiguous timeout cannot double-spend.
  String _id() =>
      uuid?.call() ?? 'tx_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<Either<Failure, AccountView>> getAccount() async {
    try {
      return Right(await _currentView());
    } catch (_) {
      return const Left(CacheFailure('Could not load account'));
    }
  }

  /// Confirmed balance + outbox, combined. The derivation lives in
  /// [AccountView]; this just gathers the three numbers it needs.
  Future<AccountView> _currentView() async {
    var account = await local.getAccount();
    if (account == null) {
      account = await remote.fetchAccount();
      await local.upsertAccount(account);
    }
    return AccountView(
      account: account,
      pendingOutCents: await local.pendingOutCents(),
      pendingInCents: await local.pendingInCents(),
    );
  }

  @override
  Future<Either<Failure, AccountView>> refresh() async {
    try {
      // Ledger first, balance second. If a transfer lands between the two
      // calls it will be inside the balance but missing from the ledger, so
      // the client keeps counting it as pending and shows slightly LESS money
      // than it has — which self-corrects on the next refresh. The opposite
      // order would show more money than exists, and could let the user
      // overdraw. A single combined endpoint would remove the choice.
      final ledger = await remote.fetchTransactions();
      final account = await remote.fetchAccount();

      await local.reconcile(
        serverTransactions: ledger,
        account: account,
      );
      return Right(await _currentView());
    } on AuthExpiredException catch (e) {
      return Left(AuthExpiredFailure(e.message));
    } on WalletException catch (e) {
      // Offline is not an error here — the cached view is still valid, that is
      // the point of the local DB being the source of truth.
      return Left(NetworkFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('Could not refresh'));
    }
  }

  @override
  Future<Either<Failure, List<WalletTransaction>>> getTransactions() async {
    try {
      return Right(await local.getTransactions());
    } catch (_) {
      return const Left(CacheFailure('Could not load transactions'));
    }
  }

  @override
  Future<Either<Failure, WalletTransaction>> transfer({
    required String toCounterparty,
    required int amountCents,
  }) async {
    try {
      final view = await _currentView();

      // Checked against the DERIVED figure, not the confirmed one — otherwise
      // three offline transfers would each pass against the same untouched
      // balance and the user could overdraw while disconnected.
      //
      // This is optimistic, not authoritative: the confirmed balance can be
      // stale (money spent on another device), so the server can still reject
      // a transfer that passed here. Rejection has to be handled on the way
      // back, not prevented on the way out.
      if (view.availableCents < amountCents) {
        return const Left(TransferFailure('Insufficient balance'));
      }

      final tx = TransactionModel(
        id: _id(),
        counterparty: toCounterparty,
        amountCents: amountCents,
        direction: TxDirection.debit,
        timestamp: DateTime.now(),
        status: const Pending(),
      );

      // Write locally first (offline-first): the transfer is durable even if
      // the network call fails. The account row is untouched — the debit is
      // visible through the pending sum until the server confirms it.
      await local.enqueueTransfer(tx);

      try {
        final ack = await remote.pushTransfer(
          idempotencyKey: tx.id,
          toCounterparty: toCounterparty,
          amountCents: amountCents,
        );
        // Leaves the pending set and enters the confirmed balance together,
        // so the derived figure does not move. That is the no-flicker property.
        await local.confirmTransfer(
          txId: tx.id,
          confirmedBalanceCents: ack.balanceCents,
          serverTime: ack.serverTime,
        );
      } on RejectedException catch (e) {
        // Terminal. Retrying would fail identically forever, so the row is
        // closed out now. The user is standing right here, so they are told —
        // silently queueing a transfer that can never succeed would be worse.
        await local.markRejected(txId: tx.id, reason: e.message);
        return Left(RejectedFailure(e.message));
      } on AuthExpiredException catch (e) {
        // Stays queued, but backoff is the wrong response — this needs the
        // user to re-authenticate before anything will get through.
        return Left(AuthExpiredFailure(e.message));
      } catch (_) {
        // Transient, or the request may have landed and the reply was lost.
        // Either way it stays in the outbox for a later retry, and the
        // idempotency key makes that retry safe. Still a success locally —
        // the user's money moved the moment it hit the local DB.
      }
      return Right(tx);
    } catch (_) {
      return const Left(TransferFailure());
    }
  }
}
