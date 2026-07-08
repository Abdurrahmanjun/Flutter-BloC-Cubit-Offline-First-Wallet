import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../dashboard/dashboard_page.dart';
import 'cubit/auth_cubit.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.unlocked) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const DashboardPage()),
          );
        }
      },
      builder: (context, state) {
        final busy = state.status == AuthStatus.authenticating;
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 72),
                  const SizedBox(height: 16),
                  Text('Offline-First Wallet',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock with native Android biometrics',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed:
                        busy ? null : () => context.read<AuthCubit>().unlock(),
                    icon: const Icon(Icons.fingerprint),
                    label: Text(busy ? 'Authenticating…' : 'Unlock'),
                  ),
                  if (state.message.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(state.message,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
