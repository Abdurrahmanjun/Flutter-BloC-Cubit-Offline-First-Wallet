import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/account.dart';
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
        super(const DashboardState());

  final GetAccount _getAccount;
  final GetTransactions _getTransactions;

  Future<void> load() async {
    emit(state.copyWith(status: DashboardStatus.loading));
    final accResult = await _getAccount();
    final txResult = await _getTransactions();

    accResult.fold(
      (f) => emit(state.copyWith(status: DashboardStatus.error, message: f.message)),
      (account) => txResult.fold(
        (f) => emit(state.copyWith(status: DashboardStatus.error, message: f.message)),
        (txs) => emit(state.copyWith(
          status: DashboardStatus.loaded,
          account: account,
          transactions: txs,
        )),
      ),
    );
  }
}
