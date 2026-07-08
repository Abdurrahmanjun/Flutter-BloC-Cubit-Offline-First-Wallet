part of 'auth_cubit.dart';

enum AuthStatus { locked, authenticating, unlocked, unavailable, error }

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.locked, this.message = ''});
  final AuthStatus status;
  final String message;

  AuthState copyWith({AuthStatus? status, String? message}) =>
      AuthState(status: status ?? this.status, message: message ?? this.message);

  @override
  List<Object?> get props => [status, message];
}
