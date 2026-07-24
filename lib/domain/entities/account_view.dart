import 'package:equatable/equatable.dart';
import 'account.dart';

/// What the UI actually shows: the server-confirmed [Account] plus everything
/// still sitting in the outbox, combined into a spendable figure.
///
///     available = confirmed − pendingOut + pendingIn
///
/// Deriving rather than storing is what keeps the balance stable across a
/// sync. When a queued debit confirms it leaves the pending set and enters the
/// server balance *in the same step*, so the net change on screen is zero.
/// When it is rejected it leaves the pending set having never entered the
/// server balance, so the money comes back — correctly, and without anyone
/// hand-patching a number.
class AccountView extends Equatable {
  const AccountView({
    required this.account,
    this.pendingOutCents = 0,
    this.pendingInCents = 0,
  });

  final Account account;

  /// Sum of queued debits not yet confirmed by the server.
  final int pendingOutCents;

  /// Sum of queued credits not yet confirmed (e.g. a reversal awaiting sync).
  final int pendingInCents;

  int get confirmedCents => account.confirmedBalanceCents;

  /// The spendable figure — headline on the balance card, and the number the
  /// insufficient-balance check runs against.
  int get availableCents => confirmedCents - pendingOutCents + pendingInCents;

  bool get hasPending => pendingOutCents != 0 || pendingInCents != 0;

  String get id => account.id;
  String get holderName => account.holderName;
  String get currency => account.currency;

  double get available => availableCents / 100.0;

  @override
  List<Object?> get props => [account, pendingOutCents, pendingInCents];
}
