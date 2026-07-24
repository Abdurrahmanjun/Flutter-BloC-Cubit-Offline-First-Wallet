part of 'auth_cubit.dart';

/// Sealed so the biometric flow's states are exhaustively handled by callers.
sealed class AuthState extends Equatable {
  const AuthState();

  /// User-facing message; empty for states that carry none.
  String get message => '';

  @override
  List<Object?> get props => [message];
}

/// Idle / not authenticated. [message] carries a reason (e.g. "Canceled").
class AuthLocked extends AuthState {
  const AuthLocked([this.message = '']);
  @override
  final String message;
}

/// BiometricPrompt is on screen.
class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

/// Authenticated — proceed to the dashboard.
class AuthUnlocked extends AuthState {
  const AuthUnlocked();
}

/// No biometrics enrolled / hardware unavailable.
class AuthUnavailable extends AuthState {
  const AuthUnavailable(this.message);
  @override
  final String message;
}

/// Authentication attempted but failed.
class AuthError extends AuthState {
  const AuthError(this.message);
  @override
  final String message;
}
