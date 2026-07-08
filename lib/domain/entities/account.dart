import 'package:equatable/equatable.dart';

class Account extends Equatable {
  const Account({
    required this.id,
    required this.holderName,
    required this.balanceCents,
    required this.currency,
  });

  final String id;
  final String holderName;
  final int balanceCents; // money as integer cents — never use double for money
  final String currency;

  double get balance => balanceCents / 100.0;

  Account copyWith({int? balanceCents}) => Account(
        id: id,
        holderName: holderName,
        balanceCents: balanceCents ?? this.balanceCents,
        currency: currency,
      );

  @override
  List<Object?> get props => [id, holderName, balanceCents, currency];
}
