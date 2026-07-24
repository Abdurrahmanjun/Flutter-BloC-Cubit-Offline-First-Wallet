import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/account_view.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/get_account.dart';
import '../../../domain/usecases/get_transactions.dart';
import '../../../domain/usecases/refresh_wallet.dart';

part 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required GetAccount getAccount,
    required GetTransactions getTransactions,
    required RefreshWallet refreshWallet,
  })  : _getAccount = getAccount,
        _getTransactions = getTransactions,
        _refreshWallet = refreshWallet,
        super(const DashboardInitial());

  final GetAccount _getAccount;
  final GetTransactions _getTransactions;
  final RefreshWallet _refreshWallet;

  /// Pull-to-refresh. Reconciles with the server, then re-reads locally.
  ///
  /// A failed refresh is not an error state: the cached view is still valid
  /// and still correct — that is the point of the local DB being the source of
  /// truth. Blanking the screen because the network is down would be the
  /// online-first behaviour this app exists to avoid.
  Future<void> refresh() async {
    await _refreshWallet();
    await _read();
  }

  Future<void> load() async {
    emit(const DashboardLoading());
    await _read();
  }

  Future<void> _read() async {
    final accResult = await _getAccount();
    final txResult = await _getTransactions();

    emit(accResult.fold(
      (f) => DashboardError(f.message),
      (account) => txResult.fold(
        (f) => DashboardError(f.message),
        (txs) => DashboardLoaded(account: account, transactions: txs),
      ),
    ));
  }
}
