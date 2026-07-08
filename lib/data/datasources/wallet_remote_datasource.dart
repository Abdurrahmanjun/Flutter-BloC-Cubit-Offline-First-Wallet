import '../models/account_model.dart';

/// Mock remote API. In a real app this is Dio/Retrofit hitting a backend.
/// Kept clean-room so the repo is safe to make public.
class WalletRemoteDataSource {
  Future<AccountModel> fetchAccount() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const AccountModel(
      id: 'acc_demo',
      holderName: 'Abdurrahman J. M.',
      balanceCents: 250000,
      currency: 'USD',
    );
  }

  Future<void> pushTransfer({
    required String toCounterparty,
    required int amountCents,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Pretend the server accepted it.
  }
}
