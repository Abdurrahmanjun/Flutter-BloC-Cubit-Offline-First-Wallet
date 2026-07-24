/// In-memory wallet state. No database on purpose: restarting the server is
/// the reset button, which is what you want from a reference implementation.
class Store {
  Store({this.balanceCents = 250000});

  int balanceCents;
  final String accountId = 'acc_demo';
  final String holderName = 'Jamie Carter';
  final String currency = 'USD';

  final List<AppliedTransfer> ledger = [];

  /// Idempotency key → the response that key produced. The contract requires
  /// a replay to return this rather than an error, so a client retrying after
  /// a lost reply gets the original outcome instead of a second debit.
  ///
  /// A real server expires these (24h in the contract) and persists them —
  /// an in-memory map would lose the guarantee across a restart.
  final Map<String, AppliedTransfer> applied = {};

  AppliedTransfer? replay(String idempotencyKey) => applied[idempotencyKey];

  /// Applies a transfer. Returns null when the balance cannot cover it, which
  /// the caller turns into a terminal 422 — never a retryable error.
  AppliedTransfer? apply({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  }) {
    if (amountCents > balanceCents) return null;

    balanceCents -= amountCents;
    final applied = AppliedTransfer(
      id: idempotencyKey,
      counterparty: toCounterparty,
      amountCents: amountCents,
      balanceAfterCents: balanceCents,
      serverTime: DateTime.now().toUtc(),
    );
    this.applied[idempotencyKey] = applied;
    ledger.add(applied);
    return applied;
  }
}

class AppliedTransfer {
  const AppliedTransfer({
    required this.id,
    required this.counterparty,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.serverTime,
  });

  final String id;
  final String counterparty;
  final int amountCents;
  final int balanceAfterCents;
  final DateTime serverTime;

  Map<String, Object?> toAck() => {
        'id': id,
        'balanceCents': balanceAfterCents,
        'serverTimestamp': serverTime.millisecondsSinceEpoch,
      };

  Map<String, Object?> toLedgerEntry() => {
        'id': id,
        'counterparty': counterparty,
        'amountCents': amountCents,
        'direction': 'debit',
        'serverTimestamp': serverTime.millisecondsSinceEpoch,
      };
}
