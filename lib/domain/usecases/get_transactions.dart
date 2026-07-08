import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/transaction.dart';
import '../repositories/wallet_repository.dart';

class GetTransactions {
  GetTransactions(this._repo);
  final WalletRepository _repo;
  Future<Either<Failure, List<WalletTransaction>>> call() =>
      _repo.getTransactions();
}
