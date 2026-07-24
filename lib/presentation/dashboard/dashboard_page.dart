import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../domain/entities/account_view.dart';
import '../history/transaction_tile.dart';
import '../transfer/transfer_page.dart';
import '../widgets/money_text.dart';
import '../widgets/page_transition.dart';
import 'cubit/dashboard_cubit.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DashboardCubit>()..load(),
      child: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: BlocBuilder<DashboardCubit, DashboardState>(
              builder: (context, state) => switch (state) {
                DashboardInitial() || DashboardLoading() =>
                  const Center(child: CircularProgressIndicator()),
                DashboardError(:final message) => Center(child: Text(message)),
                DashboardLoaded(:final account, :final transactions) =>
                  RefreshIndicator(
                  onRefresh: () => context.read<DashboardCubit>().load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _TopBar(name: account.holderName),
                      const SizedBox(height: 22),
                      _BalanceCard(account: account),
                      const SizedBox(height: 20),
                      _QuickActions(
                        onSend: () async {
                          await Navigator.of(context).push(
                            fadeSlideRoute<void>(const TransferPage()),
                          );
                          if (context.mounted) {
                            context.read<DashboardCubit>().load();
                          }
                        },
                      ),
                      const SizedBox(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent activity',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: context.tokens.textPrimary,
                            ),
                          ),
                          Text(
                            'See all',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.tokens.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (transactions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No transactions yet',
                              style: TextStyle(color: context.tokens.textMuted),
                            ),
                          ),
                        )
                      else
                        ...transactions.map((t) => TransactionTile(tx: t)),
                    ],
                  ),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.name});
  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: t.accentGradient,
            borderRadius: BorderRadius.circular(WalletTokens.rAvatar),
          ),
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                style: TextStyle(fontSize: 13, color: t.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const _ThemeToggle(),
      ],
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = ThemeController.of(context);
    return GestureDetector(
      onTap: controller.toggle,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.hairline),
        ),
        child: Icon(
          controller.isDark
              ? Icons.wb_sunny_rounded
              : Icons.nightlight_round,
          size: 18,
          color: t.textMuted,
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.account});
  final AccountView account;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        gradient: t.accentGradient,
        borderRadius: BorderRadius.circular(WalletTokens.rBalanceCard),
        boxShadow: [
          BoxShadow(
            color: t.accentStart.withValues(alpha: 0.8),
            blurRadius: 44,
            offset: const Offset(0, 22),
            spreadRadius: -20,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WalletTokens.rBalanceCard),
        child: Stack(
          children: [
            // Two blurred decorative light circles.
            Positioned(
              top: -40,
              right: -20,
              child: _blurCircle(140, Colors.white.withValues(alpha: 0.16)),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: _blurCircle(150, Colors.white.withValues(alpha: 0.10)),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Available balance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const _SyncedPill(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  MoneyText(
                    // Derived, not stored: confirmed − queued. Holds steady
                    // when a queued transfer syncs.
                    account.availableCents,
                    currency: account.currency,
                    style: context.numeric(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        account.holderName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      // Gold "chip".
                      Container(
                        width: 34,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF7D774), Color(0xFFE0A93B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blurCircle(double size, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _SyncedPill extends StatelessWidget {
  const _SyncedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(WalletTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'Synced',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onSend});
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.north_east_rounded,
            label: 'Send',
            primary: true,
            onTap: onSend,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.south_west_rounded,
            label: 'Request',
            onTap: () => _soon(context, 'Request'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.add_rounded,
            label: 'Top up',
            onTap: () => _soon(context, 'Top up'),
          ),
        ),
      ],
    );
  }

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming soon')),
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(WalletTokens.rActionTile),
            border: Border.all(color: t.hairline),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: widget.primary ? t.accentGradient : null,
                  color: widget.primary ? null : t.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: widget.primary ? Colors.white : t.accent,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
