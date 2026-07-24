import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class TransferFailure extends Failure {
  const TransferFailure([super.message = 'Transfer failed']);
}

/// The sync worker branches on these three. The distinction is the whole
/// reason a queued transfer can be retried safely — or must not be.

/// Transient: offline, timeout, 5xx. Retry with backoff, stay queued.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection']);
}

/// Terminal: the server looked at it and said no (4xx business rule).
/// Never retry — the queued transfer must be reversed instead.
class RejectedFailure extends Failure {
  const RejectedFailure([super.message = 'Rejected by the server']);
}

/// Credentials expired. Park the queue; backoff would just burn attempts.
class AuthExpiredFailure extends Failure {
  const AuthExpiredFailure([super.message = 'Session expired']);
}
