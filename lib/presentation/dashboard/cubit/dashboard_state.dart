part of 'dashboard_cubit.dart';

enum DashboardStatus { initial, loading, loaded, error }

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.account,
    this.transactions = const [],
    this.message = '',
  });

  final DashboardStatus status;
  final Account? account;
  final List<WalletTransaction> transactions;
  final String message;

  DashboardState copyWith({
    DashboardStatus? status,
    Account? account,
    List<WalletTransaction>? transactions,
    String? message,
  }) =>
      DashboardState(
        status: status ?? this.status,
        account: account ?? this.account,
        transactions: transactions ?? this.transactions,
        message: message ?? this.message,
      );

  @override
  List<Object?> get props => [status, account, transactions, message];
}
