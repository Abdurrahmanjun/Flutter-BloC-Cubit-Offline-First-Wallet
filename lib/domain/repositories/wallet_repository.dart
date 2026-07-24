import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/account_view.dart';
import '../entities/transaction.dart';

abstract class WalletRepository {
  /// Offline-first: always returns from local cache. The spendable figure is
  /// derived from the server-confirmed balance minus whatever is still queued,
  /// so it stays stable when a queued transfer syncs.
  Future<Either<Failure, AccountView>> getAccount();

  Future<Either<Failure, List<WalletTransaction>>> getTransactions();

  /// Pulls a server snapshot and folds it in. Safe to call while transfers are
  /// queued: anything the server already knows about is settled by id first,
  /// so a pending debit is never subtracted from a balance that already
  /// excludes it.
  Future<Either<Failure, AccountView>> refresh();

  Future<Either<Failure, WalletTransaction>> transfer({
    required String toCounterparty,
    required int amountCents,
  });
}
