import '../../domain/entities/account.dart';

class AccountModel extends Account {
  const AccountModel({
    required super.id,
    required super.holderName,
    required super.balanceCents,
    required super.currency,
  });

  factory AccountModel.fromMap(Map<String, dynamic> map) => AccountModel(
        id: map['id'] as String,
        holderName: map['holder_name'] as String,
        balanceCents: map['balance_cents'] as int,
        currency: map['currency'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'holder_name': holderName,
        'balance_cents': balanceCents,
        'currency': currency,
      };
}
