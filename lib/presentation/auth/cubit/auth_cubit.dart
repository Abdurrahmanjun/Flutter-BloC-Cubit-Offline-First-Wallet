import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/platform/biometric_authenticator.dart';

part 'auth_state.dart';

/// Simple, linear flow → Cubit is the right tool (no event log needed).
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._biometric) : super(const AuthState());
  final BiometricAuthenticator _biometric;

  Future<void> unlock() async {
    emit(state.copyWith(status: AuthStatus.authenticating));

    if (!await _biometric.isAvailable()) {
      emit(state.copyWith(
          status: AuthStatus.unavailable,
          message: 'Biometrics not set up on this device'));
      return;
    }

    final result = await _biometric.authenticate();
    switch (result) {
      case BiometricResult.success:
        emit(state.copyWith(status: AuthStatus.unlocked));
      case BiometricResult.canceled:
        emit(state.copyWith(status: AuthStatus.locked, message: 'Canceled'));
      case BiometricResult.unavailable:
        emit(state.copyWith(
            status: AuthStatus.unavailable, message: 'Biometrics unavailable'));
      case BiometricResult.failed:
        emit(state.copyWith(
            status: AuthStatus.error, message: 'Authentication failed'));
    }
  }
}
