import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(this.cents, {super.key, this.currency = 'USD', this.style});
  final int cents;
  final String currency;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(symbol: currency == 'USD' ? '\$' : '$currency ');
    return Text(f.format(cents / 100.0), style: style);
  }
}
