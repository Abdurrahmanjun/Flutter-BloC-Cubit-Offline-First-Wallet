import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injector.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/sync/sync_service.dart';
import 'presentation/auth/auth_page.dart';
import 'presentation/auth/cubit/auth_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initInjector();
  // Drains anything left queued by a previous session, then follows
  // connectivity. Not awaited: a slow or failing sync must never delay first
  // paint — the UI reads the local DB and does not need the network.
  unawaited(sl<SyncService>().start());
  runApp(const WalletApp());
}

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});

  @override
  State<WalletApp> createState() => _WalletAppState();
}

class _WalletAppState extends State<WalletApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Connectivity events do not arrive while backgrounded, so an app coming
    // back to the foreground can be online with a stale queue and no event on
    // the way. Resume is its own trigger.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(sl<SyncService>().onResumed()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // App-wide light/dark switch. Exposed to descendants via
    // [ThemeController.of] so the Home screen's moon/sun toggle can flip it.
    return ThemeController(
      child: Builder(
        builder: (context) {
          final mode = ThemeController.of(context).mode;
          return MaterialApp(
            title: 'Offline-First Wallet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: BlocProvider(
              create: (_) => sl<AuthCubit>(),
              child: const AuthPage(),
            ),
          );
        },
      ),
    );
  }
}
