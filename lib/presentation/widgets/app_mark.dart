import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// The wallet "app mark": a rounded accent-gradient square with a white wallet
/// glyph and a coloured glow. Optionally floats up and down (used on Unlock).
class AppMark extends StatefulWidget {
  const AppMark({this.size = 96, this.float = false, super.key});

  final double size;
  final bool float;

  @override
  State<AppMark> createState() => _AppMarkState();
}

class _AppMarkState extends State<AppMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    if (widget.float) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Radius scales with size so smaller marks still look right.
    final radius = WalletTokens.rAppMark * (widget.size / 96);
    final mark = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.accentStart, t.accentEnd],
          // 150deg for the mark, per the handoff.
          begin: const Alignment(-0.87, -1),
          end: const Alignment(0.87, 1),
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: t.accentStart.withValues(alpha: 0.55),
            blurRadius: 44,
            offset: const Offset(0, 22),
            spreadRadius: -20,
          ),
        ],
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        color: Colors.white,
        size: widget.size * 0.46,
      ),
    );

    if (!widget.float) return mark;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // translateY ±9px over the cycle.
        final dy = -9 * Curves.easeInOut.transform(_c.value);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: mark,
    );
  }
}
