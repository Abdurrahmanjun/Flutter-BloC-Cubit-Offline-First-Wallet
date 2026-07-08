import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/account.dart';
import '../entities/transaction.dart';

abstract class WalletRepository {
  /// Offline-first: always returns from local cache; refreshes from remote when online.
  Future<Either<Failure, Account>> getAccount();
  Future<Either<Failure, List<WalletTransaction>>> getTransactions();
  Future<Either<Failure, WalletTransaction>> transfer({
    required String toCounterparty,
    required int amountCents,
  });
}
