import '../models/account_model.dart';
import '../models/remote_transaction.dart';
import '../models/transfer_ack.dart';

/// The wallet backend, as the client sees it.
///
/// Two implementations exist: an in-process fake with failure injection, which
/// everything above this line is tested against, and an HTTP client that talks
/// to the reference server. Both must behave identically, because the client's
/// correctness rests on three promises that live on the far side of this
/// boundary:
///
///  * a replayed idempotency key returns the original outcome, never a second
///    debit;
///  * every accepted write reports the authoritative balance back;
///  * failures are distinguishable — "never arrived" and "arrived and was
///    refused" demand opposite responses.
///
/// Implementations signal failure by throwing [WalletException] subtypes; a
/// generic error is treated as transient, which is the safe default.
abstract class WalletRemoteDataSource {
  Future<AccountModel> fetchAccount();

  /// The server's ledger. Reconciliation matches these ids against local rows,
  /// so ids must be exactly what the client sent as idempotency keys.
  Future<List<RemoteTransaction>> fetchTransactions();

  Future<TransferAck> pushTransfer({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  });
}
