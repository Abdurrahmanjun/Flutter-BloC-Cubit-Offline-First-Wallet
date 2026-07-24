import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/core/theme/app_theme.dart';
import 'package:offline_first_wallet/domain/entities/account.dart';
import 'package:offline_first_wallet/domain/entities/account_view.dart';
import 'package:offline_first_wallet/domain/entities/sync_status.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';
import 'package:offline_first_wallet/domain/repositories/wallet_sync.dart';
import 'package:offline_first_wallet/domain/usecases/get_account.dart';
import 'package:offline_first_wallet/domain/usecases/get_transactions.dart';
import 'package:offline_first_wallet/domain/usecases/refresh_wallet.dart';
import 'package:offline_first_wallet/presentation/dashboard/cubit/dashboard_cubit.dart';
import 'package:offline_first_wallet/presentation/history/transaction_tile.dart';

class _MockGetAccount extends Mock implements GetAccount {}

class _MockGetTransactions extends Mock implements GetTransactions {}

class _MockRefreshWallet extends Mock implements RefreshWallet {}

class _FakeSync implements WalletSync {
  final _controller = StreamController<SyncStatus>.broadcast();
  @override
  SyncStatus current = const SyncIdle();
  var resumed = 0;
  final cancelled = <String>[];

  void emit(SyncStatus status) {
    current = status;
    _controller.add(status);
  }

  @override
  Stream<SyncStatus> get status => _controller.stream;
  @override
  Future<void> sync() async {}
  @override
  Future<void> resume() async => resumed++;
  @override
  Future<void> cancelQueued(String txId) async => cancelled.add(txId);

  Future<void> dispose() => _controller.close();
}

const _account = Account(
  id: 'acc_demo',
  holderName: 'Jamie Carter',
  confirmedBalanceCents: 250000,
  currency: 'USD',
);

void main() {
  late _MockGetAccount getAccount;
  late _MockGetTransactions getTransactions;
  late _MockRefreshWallet refreshWallet;
  late _FakeSync sync;

  setUp(() {
    getAccount = _MockGetAccount();
    getTransactions = _MockGetTransactions();
    refreshWallet = _MockRefreshWallet();
    sync = _FakeSync();
  });

  tearDown(() => sync.dispose());

  void stub({int pendingOut = 0, List<WalletTransaction> txs = const []}) {
    when(getAccount.call).thenAnswer((_) async =>
        Right(AccountView(account: _account, pendingOutCents: pendingOut)));
    when(getTransactions.call).thenAnswer((_) async => Right(txs));
    when(refreshWallet.call)
        .thenAnswer((_) async => const Left(NetworkFailure()));
  }

  DashboardCubit buildCubit() => DashboardCubit(
        getAccount: getAccount,
        getTransactions: getTransactions,
        refreshWallet: refreshWallet,
        sync: sync,
      );

  group('the cubit', () {
    test('reports the derived balance, not the confirmed one', () async {
      stub(pendingOut: 10000);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      final loaded = cubit.state as DashboardLoaded;
      expect(loaded.account.availableCents, 240000);
      expect(loaded.account.confirmedCents, 250000);
    });

    test('re-reads when the worker settles something in the background',
        () async {
      stub(pendingOut: 10000);
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();
      expect((cubit.state as DashboardLoaded).account.availableCents, 240000);

      // The worker confirms it while this screen is open.
      stub();
      sync.emit(const SyncIdle());
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DashboardLoaded).account.availableCents, 250000,
          reason: 'the screen must not keep showing money as queued after it '
              'has landed');
    });

    test('a failed refresh keeps the cached view instead of erroring',
        () async {
      stub(pendingOut: 10000);
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.refresh();

      expect(cubit.state, isA<DashboardLoaded>(),
          reason: 'offline is the normal case, not an error screen');
      expect((cubit.state as DashboardLoaded).account.availableCents, 240000);
    });

    test('carries the worker state into the rendered state', () async {
      stub();
      final cubit = buildCubit();
      addTearDown(cubit.close);

      sync.current = const SyncParked(reason: 'nope', blockedTxId: 'tx_0');
      await cubit.load();

      expect((cubit.state as DashboardLoaded).sync, isA<SyncParked>());
    });
  });

  group('the transaction tile', () {
    Future<void> pump(WidgetTester tester, WalletTransaction tx) =>
        tester.pumpWidget(MaterialApp(
          // The tile reads WalletTokens off the theme; a bare MaterialApp
          // has no such extension.
          theme: AppTheme.light,
          home: Scaffold(body: TransactionTile(tx: tx)),
        ));

    WalletTransaction txWith(TxStatus status) => WalletTransaction(
          id: 't1',
          counterparty: 'alice',
          amountCents: 10000,
          direction: TxDirection.debit,
          timestamp: DateTime(2026, 1, 1, 9),
          status: status,
        );

    testWidgets('a queued transfer says so', (tester) async {
      await pump(tester, txWith(const Pending()));

      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Queued · syncs when you reconnect'), findsOneWidget);
    });

    testWidgets('a rejected transfer shows the reason, not a date',
        (tester) async {
      await pump(tester, txWith(const Rejected('INSUFFICIENT_FUNDS')));

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('INSUFFICIENT_FUNDS'), findsOneWidget);
      expect(find.text('Queued'), findsNothing);
    });

    testWidgets('a settled transfer shows the server time and no badge',
        (tester) async {
      await pump(
          tester, txWith(Synced(serverTime: DateTime(2026, 2, 3, 15, 30))));

      expect(find.text('Queued'), findsNothing);
      expect(find.text('Failed'), findsNothing);
      expect(find.text('Feb 3, 2026 · 3:30 PM'), findsOneWidget);
    });
  });
}
