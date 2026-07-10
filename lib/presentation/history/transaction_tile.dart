import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/transaction.dart';
import '../widgets/money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.tx, super.key});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final debit = tx.direction == TxDirection.debit;
    // Unsynced transfers are queued offline — the core offline-first cue.
    final queued = !tx.synced;

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
                    if (queued) ...[
                      const SizedBox(width: 8),
                      _QueuedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  queued
                      ? 'Queued · syncs when you reconnect'
                      : DateFormat('MMM d, y · h:mm a').format(tx.timestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: queued ? t.accent : t.textMuted,
                    fontWeight: queued ? FontWeight.w600 : FontWeight.w400,
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
              color: debit ? t.textPrimary : t.success,
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

class _QueuedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WalletTokens.rPill),
      ),
      child: Text(
        'Queued',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: t.accent,
        ),
      ),
    );
  }
}
