import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/tx_status.dart';
import '../widgets/money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.tx, super.key});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final debit = tx.direction == TxDirection.debit;

    // Exhaustive over TxStatus: a fourth state would fail to compile here
    // rather than quietly rendering as an ordinary settled transfer.
    final (badge, caption, captionColor) = switch (tx.status) {
      Pending() => (
          'Queued',
          'Queued · syncs when you reconnect',
          t.accent,
        ),
      Rejected(:final reason) => (
          'Failed',
          reason,
          t.danger,
        ),
      Synced() => (
          null,
          DateFormat('MMM d, y · h:mm a').format(tx.displayTime),
          t.textMuted,
        ),
    };
    final rejected = tx.status is Rejected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (debit ? t.accent : t.success).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(WalletTokens.rAvatar),
            ),
            child: Icon(
              debit ? Icons.north_east_rounded : Icons.south_west_rounded,
              size: 20,
              color: debit ? t.accent : t.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _capitalize(tx.counterparty),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      _StatusBadge(label: badge, color: captionColor),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: captionColor,
                    fontWeight:
                        badge == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            debit ? -tx.amountCents : tx.amountCents,
            style: context.numeric(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              // A rejected transfer never moved money, so it is struck through
              // rather than shown as a real debit sitting in the history.
              color: rejected
                  ? t.textFaint
                  : (debit ? t.textPrimary : t.success),
            ).copyWith(
              decoration: rejected ? TextDecoration.lineThrough : null,
              decorationColor: rejected ? t.textFaint : null,
            ),
          ),
        ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WalletTokens.rPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
