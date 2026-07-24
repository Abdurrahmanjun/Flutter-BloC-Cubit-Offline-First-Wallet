import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../success/success_page.dart';
import '../widgets/gradient_button.dart';
import '../widgets/page_transition.dart';
import 'bloc/transfer_bloc.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _toController = TextEditingController();
  final _amountController = TextEditingController();

  // Suggested contacts — tapping a chip fills the recipient.
  static const _contacts = ['maya lawson', 'theo bennett', 'nina park'];

  @override
  void initState() {
    super.initState();
    _toController.addListener(_onChanged);
    _amountController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  double get _amount => double.tryParse(_amountController.text) ?? 0;
  bool get _valid => _toController.text.trim().isNotEmpty && _amount > 0;

  String get _ctaLabel {
    final f = NumberFormat.currency(symbol: '\$');
    return 'Send ${f.format(_amount)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BlocProvider(
      create: (_) => sl<TransferBloc>(),
      child: BlocConsumer<TransferBloc, TransferState>(
        listener: (context, state) {
          switch (state) {
            case TransferSucceeded():
              // Replace Send with Success; its "Done" returns to Home.
              Navigator.of(context).pushReplacement(
                fadeSlideRoute<void>(
                  SuccessPage(
                    amountCents: (_amount * 100).round(),
                    recipient: _toController.text.trim(),
                  ),
                ),
              );
            case TransferFailed(:final message):
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(message)));
            case TransferIdle():
            case TransferInProgress():
              break;
          }
        },
        builder: (context, state) {
          final submitting = state is TransferInProgress;
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text('Send money'),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                child: Column(
                  children: [
                    const Spacer(),
                    _AmountBlock(controller: _amountController),
                    const Spacer(),
                    _RecipientField(controller: _toController),
                    const SizedBox(height: 14),
                    _ContactChips(
                      contacts: _contacts,
                      onPick: (name) {
                        _toController.text = name;
                        _toController.selection = TextSelection.collapsed(
                          offset: name.length,
                        );
                      },
                    ),
                    const Spacer(flex: 2),
                    GradientButton(
                      label: _ctaLabel,
                      enabled: _valid,
                      busy: submitting,
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        final cents = (_amount * 100).round();
                        context.read<TransferBloc>().add(
                              TransferSubmitted(
                                toCounterparty: _toController.text.trim(),
                                amountCents: cents,
                              ),
                            );
                      },
                    ),
                  ],
                ),
              ),
            ),
            backgroundColor: t.screenBackground,
          );
        },
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Text(
          'Amount',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 6),
              child: Text(
                '\$',
                style: context.numeric(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: t.textFaint,
                ),
              ),
            ),
            IntrinsicWidth(
              child: TextField(
                controller: controller,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                // Digits + a single decimal point only.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                cursorColor: t.accent,
                style: context.numeric(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -2,
                  color: t.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '0',
                  hintStyle: context.numeric(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    color: t.textFaint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecipientField extends StatelessWidget {
  const _RecipientField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = controller.text.trim();
    final initial = text.isEmpty ? '?' : text.characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(WalletTokens.rInput),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: t.accentGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: t.accent,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Recipient name or @handle',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: t.textFaint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactChips extends StatelessWidget {
  const _ContactChips({required this.contacts, required this.onPick});
  final List<String> contacts;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: contacts.map((name) {
          final initial = name.characters.first.toUpperCase();
          return GestureDetector(
            onTap: () => onPick(name),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(WalletTokens.rPill),
                border: Border.all(color: t.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: t.accentGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
