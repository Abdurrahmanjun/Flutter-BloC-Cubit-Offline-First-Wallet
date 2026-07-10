import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import '../widgets/money_text.dart';

/// Payment confirmation. Reached via [TransferBloc] success; "Done" pops back
/// to Home. The offline note reinforces the queued-until-reconnect semantics.
class SuccessPage extends StatelessWidget {
  const SuccessPage({
    required this.amountCents,
    required this.recipient,
    super.key,
  });

  final int amountCents;
  final String recipient;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.screenBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const _AnimatedCheck(),
              const SizedBox(height: 28),
              Text(
                'Payment sent',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your transfer is on its way',
                style: TextStyle(fontSize: 15, color: t.textMuted),
              ),
              const SizedBox(height: 26),
              MoneyText(
                -amountCents,
                style: context.numeric(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'to ${_capitalize(recipient)}',
                style: TextStyle(fontSize: 14, color: t.textMuted),
              ),
              const SizedBox(height: 22),
              const _OfflineNote(),
              const Spacer(flex: 4),
              GradientButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WalletTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 15, color: t.accent),
          const SizedBox(width: 8),
          Text(
            'Queued offline · syncs when you reconnect',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCheck extends StatefulWidget {
  const _AnimatedCheck();

  @override
  State<_AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<_AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Circle draws over the first ~0.55s, the tick over the delayed ~0.4s.
    final circle = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.58, curve: Curves.easeOut),
    );
    final tick = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.42, 1.0, curve: Curves.easeOut),
    );
    return SizedBox(
      width: 104,
      height: 104,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _CheckPainter(
            color: t.success,
            circleProgress: circle.value,
            tickProgress: tick.value,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.color,
    required this.circleProgress,
    required this.tickProgress,
  });

  final Color color;
  final double circleProgress;
  final double tickProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Soft tint fill behind the ring.
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 - 3,
      Paint()..color = color.withValues(alpha: 0.12),
    );

    // Ring — swept from the top.
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 3,
    );
    canvas.drawArc(rect, -1.5708, 6.2832 * circleProgress, false, stroke);

    // Tick — two segments drawn progressively.
    final p1 = Offset(size.width * 0.30, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.66);
    final p3 = Offset(size.width * 0.72, size.height * 0.37);

    final path = Path()..moveTo(p1.dx, p1.dy);
    final firstLen = (p2 - p1).distance;
    final secondLen = (p3 - p2).distance;
    final total = firstLen + secondLen;
    final drawn = total * tickProgress;

    if (drawn <= firstLen) {
      final f = firstLen == 0 ? 0.0 : drawn / firstLen;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final f = secondLen == 0 ? 0.0 : (drawn - firstLen) / secondLen;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * f, p2.dy + (p3.dy - p2.dy) * f);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.circleProgress != circleProgress || old.tickProgress != tickProgress;
}
