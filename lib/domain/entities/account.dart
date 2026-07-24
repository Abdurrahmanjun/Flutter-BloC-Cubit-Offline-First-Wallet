import 'package:equatable/equatable.dart';

class Account extends Equatable {
  const Account({
    required this.id,
    required this.holderName,
    required this.confirmedBalanceCents,
    required this.currency,
  });

  final String id;
  final String holderName;

  /// The balance the SERVER has confirmed. Written only from a server
  /// response — never by a local transfer.
  ///
  /// Local transfers do not touch this. They land in the outbox as pending
  /// rows, and the spendable figure is derived in [AccountView]. Mutating this
  /// number locally is what makes money visibly flicker: overwrite it on the
  /// next refresh and a pending debit reappears, then vanishes again when the
  /// sync completes.
  final int confirmedBalanceCents;

  final String currency; // money as integer cents — never use double for money

  double get confirmedBalance => confirmedBalanceCents / 100.0;

  Account copyWith({int? confirmedBalanceCents}) => Account(
        id: id,
        holderName: holderName,
        confirmedBalanceCents:
            confirmedBalanceCents ?? this.confirmedBalanceCents,
        currency: currency,
      );

  @override
  List<Object?> get props => [id, holderName, confirmedBalanceCents, currency];
}
