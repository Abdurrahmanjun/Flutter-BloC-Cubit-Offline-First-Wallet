import 'package:equatable/equatable.dart';

enum TxDirection { debit, credit }

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.counterparty,
    required this.amountCents,
    required this.direction,
    required this.timestamp,
    this.synced = false,
  });

  final String id;
  final String counterparty;
  final int amountCents;
  final TxDirection direction;
  final DateTime timestamp;
  final bool synced;

  double get amount => amountCents / 100.0;

  @override
  List<Object?> get props =>
      [id, counterparty, amountCents, direction, timestamp, synced];
}
