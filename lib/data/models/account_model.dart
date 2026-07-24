import '../../domain/entities/account.dart';

class AccountModel extends Account {
  const AccountModel({
    required super.id,
    required super.holderName,
    required super.confirmedBalanceCents,
    required super.currency,
  });

  factory AccountModel.fromMap(Map<String, dynamic> map) => AccountModel(
        id: map['id'] as String,
        holderName: map['holder_name'] as String,
        confirmedBalanceCents: map['confirmed_balance_cents'] as int,
        currency: map['currency'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'holder_name': holderName,
        'confirmed_balance_cents': confirmedBalanceCents,
        'currency': currency,
      };
}
