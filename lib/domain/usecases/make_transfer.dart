import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/transaction.dart';
import '../repositories/wallet_repository.dart';

class MakeTransfer {
  MakeTransfer(this._repo);
  final WalletRepository _repo;

  Future<Either<Failure, WalletTransaction>> call({
    required String toCounterparty,
    required int amountCents,
  }) {
    if (amountCents <= 0) {
      return Future.value(const Left(TransferFailure('Amount must be positive')));
    }
    return _repo.transfer(toCounterparty: toCounterparty, amountCents: amountCents);
  }
}
