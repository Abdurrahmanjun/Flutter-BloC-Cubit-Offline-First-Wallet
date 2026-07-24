/// Data-layer exceptions. The remote datasource throws these; the repository
/// maps them to the matching [Failure]. They exist so the sync worker can tell
/// "the server never saw it" apart from "the server said no" — the two demand
/// opposite responses (retry vs. reverse), and a bare `catch (_)` cannot.
library;

sealed class WalletException implements Exception {
  const WalletException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Transient. The request may or may not have been applied — see the note on
/// idempotency below. Retry with backoff.
class NetworkException extends WalletException {
  const NetworkException([super.message = 'No connection']);
}

/// Terminal. A business rule rejected it (insufficient funds, bad recipient,
/// frozen account). Retrying will fail identically, forever.
class RejectedException extends WalletException {
  const RejectedException([super.message = 'Rejected by the server']);
}

/// Credentials expired. Needs re-auth, not backoff.
class AuthExpiredException extends WalletException {
  const AuthExpiredException([super.message = 'Session expired']);
}
