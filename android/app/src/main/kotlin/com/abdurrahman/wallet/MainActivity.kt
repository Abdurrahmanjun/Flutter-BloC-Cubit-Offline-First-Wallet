package com.abdurrahman.wallet

import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The differentiator: instead of the `local_auth` plugin, we implement the
 * biometric bridge by hand.
 *
 * Dart calls MethodChannel("com.abdurrahman.wallet/biometric"):
 *   - isAvailable()  -> Boolean
 *   - authenticate() -> Boolean (or throws PlatformException with code
 *                       "unavailable" / "canceled")
 *
 * Note: extends FlutterFragmentActivity because BiometricPrompt requires a
 * FragmentActivity host.
 */
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.abdurrahman.wallet/biometric"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isBiometricAvailable())
                    "authenticate" -> authenticate(
                        title = call.argument<String>("title") ?: "Unlock",
                        subtitle = call.argument<String>("subtitle") ?: "",
                        result = result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun isBiometricAvailable(): Boolean {
        val manager = BiometricManager.from(this)
        return manager.canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        ) == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun authenticate(title: String, subtitle: String, result: MethodChannel.Result) {
        if (!isBiometricAvailable()) {
            result.error("unavailable", "Biometrics not available", null)
            return
        }

        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(this, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                    result.success(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED ->
                            result.error("canceled", errString.toString(), null)
                        else -> result.error("failed", errString.toString(), null)
                    }
                }

                override fun onAuthenticationFailed() {
                    // A single non-match; the prompt stays open. No result yet.
                }
            })

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        prompt.authenticate(info)
    }
}
