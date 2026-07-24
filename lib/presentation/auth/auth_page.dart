import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_page.dart';
import '../widgets/app_mark.dart';
import '../widgets/page_transition.dart';
import 'cubit/auth_cubit.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  // Pulsing ring around the fingerprint button (scale .86 → 1.35, fade out).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  // Fingerprint spin while verifying.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        final busy = state is AuthAuthenticating;
        if (busy) {
          _spin.repeat();
        } else {
          _spin.stop();
          _spin.value = 0;
        }
        if (state is AuthUnlocked) {
          Navigator.of(context).pushReplacement(
            fadeSlideRoute(const DashboardPage()),
          );
        }
      },
      builder: (context, state) {
        final busy = state is AuthAuthenticating;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  const AppMark(size: 96, float: true),
                  const SizedBox(height: 34),
                  Text(
                    'Offline Wallet',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Text(
                      'Secure payments that work with or without a connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  _FingerprintButton(
                    busy: busy,
                    pulse: _pulse,
                    spin: _spin,
                    onTap: busy
                        ? null
                        : () => context.read<AuthCubit>().unlock(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    busy ? 'Verifying…' : 'Tap to unlock',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: t.textMuted,
                    ),
                  ),
                  if (state.message.isNotEmpty && !busy) ...[
                    const SizedBox(height: 10),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: t.danger),
                    ),
                  ],
                  const Spacer(flex: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 13, color: t.textFaint),
                      const SizedBox(width: 6),
                      Text(
                        'End-to-end encrypted · On-device keys',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: t.textFaint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FingerprintButton extends StatelessWidget {
  const _FingerprintButton({
    required this.busy,
    required this.pulse,
    required this.spin,
    required this.onTap,
  });

  final bool busy;
  final AnimationController pulse;
  final AnimationController spin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 150,
      height: 150,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Expanding, fading pulse ring.
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final v = pulse.value;
                final scale = 0.86 + (1.35 - 0.86) * v;
                return Opacity(
                  opacity: (1 - v).clamp(0.0, 1.0) * 0.5,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: t.accent, width: 2),
                      ),
                    ),
                  ),
                );
              },
            ),
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: t.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.hairline),
                  boxShadow: [
                    BoxShadow(
                      color: t.accentStart.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                      spreadRadius: -14,
                    ),
                  ],
                ),
                child: RotationTransition(
                  turns: spin,
                  child: Icon(Icons.fingerprint,
                      size: 44, color: t.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
