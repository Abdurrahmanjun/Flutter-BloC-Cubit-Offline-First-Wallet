import '../../domain/entities/transaction.dart';

class TransactionModel extends WalletTransaction {
  const TransactionModel({
    required super.id,
    required super.counterparty,
    required super.amountCents,
    required super.direction,
    required super.timestamp,
    super.synced,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) => TransactionModel(
        id: map['id'] as String,
        counterparty: map['counterparty'] as String,
        amountCents: map['amount_cents'] as int,
        direction: TxDirection.values[map['direction'] as int],
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        synced: (map['synced'] as int) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'counterparty': counterparty,
        'amount_cents': amountCents,
        'direction': direction.index,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };
}
