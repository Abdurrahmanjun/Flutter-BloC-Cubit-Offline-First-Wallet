/// What the server returns when it accepts a transfer.
///
/// The authoritative balance comes back on the ack so the client never has to
/// guess what the debit did — it writes what the server reports.
class TransferAck {
  const TransferAck({
    required this.id,
    required this.balanceCents,
    required this.serverTime,
  });

  /// Echoes the client-generated id that was sent as the idempotency key.
  final String id;

  /// The account balance after the server applied this transfer.
  final int balanceCents;

  /// When the server applied it. Preferred over the device's stamp for
  /// display, since device clocks drift and can be set by hand.
  final DateTime serverTime;
}
