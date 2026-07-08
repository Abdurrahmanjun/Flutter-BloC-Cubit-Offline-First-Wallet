import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injector.dart';
import 'bloc/transfer_bloc.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TransferBloc>(),
      child: BlocConsumer<TransferBloc, TransferState>(
        listener: (context, state) {
          if (state.status == TransferStatus.success) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Transfer sent')));
            Navigator.of(context).pop();
          } else if (state.status == TransferStatus.failure) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final submitting = state.status == TransferStatus.submitting;
          return Scaffold(
            appBar: AppBar(title: const Text('Send money')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _toController,
                      decoration: const InputDecoration(labelText: 'Recipient'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Amount (USD)'),
                      validator: (v) {
                        final d = double.tryParse(v ?? '');
                        if (d == null || d <= 0) return 'Enter a valid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        // Double-tap safe: TransferBloc uses droppable().
                        onPressed: submitting
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  final cents = (double.parse(
                                              _amountController.text) *
                                          100)
                                      .round();
                                  context.read<TransferBloc>().add(
                                        TransferSubmitted(
                                          toCounterparty: _toController.text,
                                          amountCents: cents,
                                        ),
                                      );
                                }
                              },
                        child: Text(submitting ? 'Sending…' : 'Send'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
