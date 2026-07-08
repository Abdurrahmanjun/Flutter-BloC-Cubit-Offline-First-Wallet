import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../datasources/wallet_local_datasource.dart';
import '../datasources/wallet_remote_datasource.dart';
import '../models/account_model.dart';
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

  String _id() =>
      uuid?.call() ?? 'tx_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<Either<Failure, Account>> getAccount() async {
    try {
      final cached = await local.getAccount();
      if (cached != null) return Right(cached);
      final remoteAcc = await remote.fetchAccount();
      await local.upsertAccount(remoteAcc);
      return Right(remoteAcc);
    } catch (_) {
      return const Left(CacheFailure('Could not load account'));
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
      final account = await local.getAccount();
      if (account == null) return const Left(CacheFailure('No account'));
      if (account.balanceCents < amountCents) {
        return const Left(TransferFailure('Insufficient balance'));
      }

      final tx = TransactionModel(
        id: _id(),
        counterparty: toCounterparty,
        amountCents: amountCents,
        direction: TxDirection.debit,
        timestamp: DateTime.now(),
        synced: false,
      );
      final updated = AccountModel(
        id: account.id,
        holderName: account.holderName,
        balanceCents: account.balanceCents - amountCents,
        currency: account.currency,
      );

      // Write locally first (offline-first): the transfer is durable even if the
      // network call fails; a background sync would reconcile `synced=false` rows.
      await local.applyTransfer(updated, tx);

      try {
        await remote.pushTransfer(
            toCounterparty: toCounterparty, amountCents: amountCents);
        await local.insertTransaction(TransactionModel(
          id: tx.id,
          counterparty: tx.counterparty,
          amountCents: tx.amountCents,
          direction: tx.direction,
          timestamp: tx.timestamp,
          synced: true,
        ));
      } catch (_) {
        // Stays synced=false for later reconciliation. Still a success locally.
      }
      return Right(tx);
    } catch (_) {
      return const Left(TransferFailure());
    }
  }
}
