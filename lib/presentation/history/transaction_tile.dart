import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/transaction.dart';
import '../widgets/money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.tx, super.key});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final debit = tx.direction == TxDirection.debit;
    return ListTile(
      leading: CircleAvatar(
        child: Icon(debit ? Icons.arrow_upward : Icons.arrow_downward),
      ),
      title: Text(tx.counterparty),
      subtitle: Text(DateFormat.yMMMd().add_jm().format(tx.timestamp)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(
            debit ? -tx.amountCents : tx.amountCents,
            style: TextStyle(
              color: debit ? Colors.redAccent : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!tx.synced)
            const Text('pending sync', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
