import 'package:flutter/services.dart';

/// Result of a native biometric attempt.
enum BiometricResult { success, failed, unavailable, canceled }

/// Bridges Flutter to native Android BiometricPrompt (Kotlin) over a
/// hand-written MethodChannel — no `local_auth` package.
///
/// This is the portfolio differentiator: it proves the author can cross the
/// Flutter↔native boundary, which most Flutter developers cannot.
class BiometricAuthenticator {
  BiometricAuthenticator([MethodChannel? channel])
      : _channel = channel ??
            const MethodChannel('com.abdurrahman.wallet/biometric');

  final MethodChannel _channel;

  /// Returns true only if the device can do biometrics right now.
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the native BiometricPrompt and maps the outcome.
  Future<BiometricResult> authenticate({
    String title = 'Unlock your wallet',
    String subtitle = 'Confirm your identity to continue',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('authenticate', {
        'title': title,
        'subtitle': subtitle,
      });
      return ok == true ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'unavailable':
          return BiometricResult.unavailable;
        case 'canceled':
          return BiometricResult.canceled;
        default:
          return BiometricResult.failed;
      }
    }
  }
}
