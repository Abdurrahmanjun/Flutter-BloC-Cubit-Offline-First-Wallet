import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/account_view.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/get_account.dart';
import '../../../domain/usecases/get_transactions.dart';

part 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required GetAccount getAccount,
    required GetTransactions getTransactions,
  })  : _getAccount = getAccount,
        _getTransactions = getTransactions,
        super(const DashboardInitial());

  final GetAccount _getAccount;
  final GetTransactions _getTransactions;

  Future<void> load() async {
    emit(const DashboardLoading());
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
