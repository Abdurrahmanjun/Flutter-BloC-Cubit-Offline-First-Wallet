import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/account_view.dart';
import '../../../domain/entities/sync_status.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/repositories/wallet_sync.dart';
import '../../../domain/usecases/get_account.dart';
import '../../../domain/usecases/get_transactions.dart';
import '../../../domain/usecases/refresh_wallet.dart';

part 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required GetAccount getAccount,
    required GetTransactions getTransactions,
    required RefreshWallet refreshWallet,
    required WalletSync sync,
  })  : _getAccount = getAccount,
        _getTransactions = getTransactions,
        _refreshWallet = refreshWallet,
        _sync = sync,
        super(const DashboardInitial()) {
    // The worker runs in the background, so a transfer can settle while this
    // screen is open. Without this the balance card would keep showing
    // "queued" for money that has already landed.
    _syncSub = _sync.status.listen((_) => unawaited(_read()));
  }

  final GetAccount _getAccount;
  final GetTransactions _getTransactions;
  final RefreshWallet _refreshWallet;
  final WalletSync _sync;

  StreamSubscription<SyncStatus>? _syncSub;

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

  /// "Try again" on a queue that stopped and will not restart on its own.
  Future<void> retrySync() => _sync.resume();

  /// Give up on the transfer blocking the queue, releasing everything behind it.
  Future<void> cancelQueued(String txId) => _sync.cancelQueued(txId);

  Future<void> _read() async {
    final accResult = await _getAccount();
    final txResult = await _getTransactions();
    if (isClosed) return;

    emit(accResult.fold(
      (f) => DashboardError(f.message),
      (account) => txResult.fold(
        (f) => DashboardError(f.message),
        (txs) => DashboardLoaded(
          account: account,
          transactions: txs,
          sync: _sync.current,
        ),
      ),
    ));
  }

  @override
  Future<void> close() async {
    await _syncSub?.cancel();
    return super.close();
  }
}
