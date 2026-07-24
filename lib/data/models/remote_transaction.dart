/// A transaction as the server knows it — the `GET /transactions` shape.
///
/// Deliberately not a [TransactionModel]: the server has no idea about local
/// status, attempts or backoff. All the client needs from this is the id
/// (to promote its own pending rows) and the server's timestamp.
class RemoteTransaction {
  const RemoteTransaction({
    required this.id,
    required this.counterparty,
    required this.amountCents,
    required this.serverTime,
  });

  final String id;
  final String counterparty;
  final int amountCents;
  final DateTime serverTime;
}
