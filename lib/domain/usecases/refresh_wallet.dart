import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/account_view.dart';
import '../repositories/wallet_repository.dart';

class RefreshWallet {
  RefreshWallet(this._repo);
  final WalletRepository _repo;
  Future<Either<Failure, AccountView>> call() => _repo.refresh();
}
