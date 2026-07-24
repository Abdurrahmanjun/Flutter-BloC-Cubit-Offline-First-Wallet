import '../../domain/entities/transaction.dart';
import '../../domain/entities/tx_status.dart';

/// On-disk codes for [TxStatus]. These are persisted values — changing a
/// number silently reinterprets every existing row, so they are append-only.
///
/// 0 and 1 are deliberately the old `synced` bool's values, which is what let
/// the v3 migration rename the column and stop there.
abstract final class TxStatusCode {
  static const pending = 0;
  static const synced = 1;
  static const rejected = 2;
}

class TransactionModel extends WalletTransaction {
  const TransactionModel({
    required super.id,
    required super.counterparty,
    required super.amountCents,
    required super.direction,
    required super.timestamp,
    super.status,
    super.reversesId,
  });

  factory TransactionModel.from(WalletTransaction tx) => TransactionModel(
        id: tx.id,
        counterparty: tx.counterparty,
        amountCents: tx.amountCents,
        direction: tx.direction,
        timestamp: tx.timestamp,
        status: tx.status,
        reversesId: tx.reversesId,
      );

  factory TransactionModel.fromMap(Map<String, dynamic> map) =>
      TransactionModel(
        id: map['id'] as String,
        counterparty: map['counterparty'] as String,
        amountCents: map['amount_cents'] as int,
        direction: TxDirection.values[map['direction'] as int],
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        status: _statusFromMap(map),
        reversesId: map['reverses_id'] as String?,
      );

  /// The discriminator column picks the variant; each one reads only its own
  /// payload columns. Unknown codes fall back to [Pending] rather than
  /// throwing — a row from a newer schema is better left queued than lost.
  static TxStatus _statusFromMap(Map<String, dynamic> map) {
    final serverTs = map['server_timestamp'] as int?;
    return switch (map['status'] as int) {
      TxStatusCode.synced => Synced(
          serverTime: serverTs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(serverTs),
        ),
      TxStatusCode.rejected =>
        Rejected((map['last_error'] as String?) ?? 'Rejected by the server'),
      _ => Pending(
          attempts: (map['attempts'] as int?) ?? 0,
          nextAttemptAt: switch (map['next_attempt_at'] as int?) {
            final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
            null => null,
          },
        ),
    };
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'counterparty': counterparty,
        'amount_cents': amountCents,
        'direction': direction.index,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'reverses_id': reversesId,
        // Payload columns are written for every row so a status change never
        // leaves a stale value behind from the variant it used to be.
        ...switch (status) {
          Pending(:final attempts, :final nextAttemptAt) => {
              'status': TxStatusCode.pending,
              'attempts': attempts,
              'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch,
              'last_error': null,
              'server_timestamp': null,
            },
          Synced(:final serverTime) => {
              'status': TxStatusCode.synced,
              'attempts': 0,
              'next_attempt_at': null,
              'last_error': null,
              'server_timestamp': serverTime?.millisecondsSinceEpoch,
            },
          Rejected(:final reason) => {
              'status': TxStatusCode.rejected,
              'attempts': 0,
              'next_attempt_at': null,
              'last_error': reason,
              'server_timestamp': null,
            },
        },
      };
}
