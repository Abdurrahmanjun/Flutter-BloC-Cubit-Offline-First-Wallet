import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injector.dart';
import '../history/transaction_tile.dart';
import '../transfer/transfer_page.dart';
import '../widgets/money_text.dart';
import 'cubit/dashboard_cubit.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DashboardCubit>()..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('My Wallet')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TransferPage()),
              );
              if (context.mounted) context.read<DashboardCubit>().load();
            },
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
          body: BlocBuilder<DashboardCubit, DashboardState>(
            builder: (context, state) {
              if (state.status == DashboardStatus.loading ||
                  state.status == DashboardStatus.initial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status == DashboardStatus.error) {
                return Center(child: Text(state.message));
              }
              final acc = state.account!;
              return RefreshIndicator(
                onRefresh: () => context.read<DashboardCubit>().load(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Available balance',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            MoneyText(acc.balanceCents,
                                currency: acc.currency,
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall),
                            const SizedBox(height: 4),
                            Text(acc.holderName),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Recent activity',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (state.transactions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No transactions yet')),
                      )
                    else
                      ...state.transactions.map((t) => TransactionTile(tx: t)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
