import '../models/account_model.dart';
import '../models/transfer_ack.dart';

/// Mock remote API. In a real app this is Dio/Retrofit hitting a backend.
/// Kept clean-room so the repo is safe to make public.
///
/// It holds a balance rather than returning a constant, because the client's
/// no-flicker guarantee depends on the server actually applying the debit:
/// a queued transfer leaves the pending set at the same moment its amount
/// enters the confirmed balance. A stateless mock would hand back the original
/// balance on confirm and the money would visibly bounce.
class WalletRemoteDataSource {
  WalletRemoteDataSource({int initialBalanceCents = 250000})
      : _balanceCents = initialBalanceCents;

  int _balanceCents;

  /// Idempotency keys the server has already applied. A repeat key returns the
  /// original outcome instead of debiting twice — which is what makes retrying
  /// after an ambiguous timeout safe.
  final Map<String, TransferAck> _applied = {};

  Future<AccountModel> fetchAccount() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return AccountModel(
      id: 'acc_demo',
      holderName: 'Abdurrahman J. M.',
      confirmedBalanceCents: _balanceCents,
      currency: 'USD',
    );
  }

  Future<TransferAck> pushTransfer({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Replay of a key we've already applied: same answer, no second debit.
    final seen = _applied[idempotencyKey];
    if (seen != null) return seen;

    _balanceCents -= amountCents;
    final ack = TransferAck(
      id: idempotencyKey,
      balanceCents: _balanceCents,
      serverTime: DateTime.now(),
    );
    _applied[idempotencyKey] = ack;
    return ack;
  }
}
