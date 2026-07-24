import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/platform/biometric_authenticator.dart';

part 'auth_state.dart';

/// Simple, linear flow → Cubit is the right tool (no event log needed).
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._biometric) : super(const AuthLocked());
  final BiometricAuthenticator _biometric;

  Future<void> unlock() async {
    emit(const AuthAuthenticating());

    if (!await _biometric.isAvailable()) {
      emit(const AuthUnavailable('Biometrics not set up on this device'));
      return;
    }

    final result = await _biometric.authenticate();
    emit(switch (result) {
      BiometricResult.success => const AuthUnlocked(),
      BiometricResult.canceled => const AuthLocked('Canceled'),
      BiometricResult.unavailable =>
        const AuthUnavailable('Biometrics unavailable'),
      BiometricResult.failed => const AuthError('Authentication failed'),
    });
  }
}
