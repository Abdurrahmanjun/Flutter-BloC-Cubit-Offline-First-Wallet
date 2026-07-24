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
  const DashboardLoaded({required this.account, required this.transactions});
  final Account account;
  final List<WalletTransaction> transactions;
  @override
  List<Object?> get props => [account, transactions];
}

/// A load failed; [message] is user-facing.
class DashboardError extends DashboardState {
  const DashboardError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
