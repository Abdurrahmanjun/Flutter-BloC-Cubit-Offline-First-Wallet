import 'package:equatable/equatable.dart';
import 'tx_status.dart';

enum TxDirection { debit, credit }

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.counterparty,
    required this.amountCents,
    required this.direction,
    required this.timestamp,
    this.status = const Pending(),
    this.reversesId,
  });

  /// Client-generated, and doubles as the server's idempotency key.
  final String id;

  final String counterparty;
  final int amountCents;
  final TxDirection direction;

  /// Device clock — fine for display, never for queue order.
  final DateTime timestamp;

  final TxStatus status;

  /// Set on a compensating entry: the id of the rejected transfer this one
  /// gives back. Lets the history show the pair together instead of an
  /// unexplained credit.
  final String? reversesId;

  double get amount => amountCents / 100.0;

  /// The stamp to show the user: the server's once it has one, the device's
  /// until then.
  DateTime get displayTime => switch (status) {
        Synced(:final serverTime) => serverTime ?? timestamp,
        _ => timestamp,
      };

  WalletTransaction copyWith({TxStatus? status}) => WalletTransaction(
        id: id,
        counterparty: counterparty,
        amountCents: amountCents,
        direction: direction,
        timestamp: timestamp,
        status: status ?? this.status,
        reversesId: reversesId,
      );

  @override
  List<Object?> get props =>
      [id, counterparty, amountCents, direction, timestamp, status, reversesId];
}
