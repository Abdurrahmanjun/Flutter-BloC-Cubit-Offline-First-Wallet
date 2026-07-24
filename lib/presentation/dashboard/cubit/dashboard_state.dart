part of 'dashboard_cubit.dart';

/// Sealed so the dashboard's `switch` is exhaustiveness-checked — the loaded
/// state carries its data non-nullably, so the UI never touches `account!`.
sealed class DashboardState extends Equatable {
  const DashboardState();
  @override
  List<Object?> get props => [];
}

/// Before the first load.
class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

/// A load is in flight.
class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

/// Loaded — [account] and [transactions] are guaranteed present.
class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.account,
    required this.transactions,
    this.sync = const SyncIdle(),
  });

  /// Carries the derived spendable balance, not the raw stored one.
  final AccountView account;
  final List<WalletTransaction> transactions;

  /// What the outbox worker is doing, so the screen can stop claiming
  /// "Synced" while transfers are still waiting to go out.
  final SyncStatus sync;

  @override
  List<Object?> get props => [account, transactions, sync];
}

/// A load failed; [message] is user-facing.
class DashboardError extends DashboardState {
  const DashboardError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
