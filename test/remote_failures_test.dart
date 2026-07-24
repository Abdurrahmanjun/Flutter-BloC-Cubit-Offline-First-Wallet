import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/core/error/exceptions.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/data/datasources/chaos_config.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/datasources/fake_wallet_remote_datasource.dart';
import 'package:offline_first_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';

const _instant = ChaosConfig(latency: Duration.zero);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late WalletLocalDataSource local;
  late FakeWalletRemoteDataSource remote;
  late WalletRepositoryImpl repo;
  var seq = 0;

  Future<void> boot({
    ChaosConfig chaos = _instant,
    int serverBalanceCents = 250000,
  }) async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await WalletLocalDataSource.createSchema(db);
    await WalletLocalDataSource.seedDemoAccount(db);
    local = WalletLocalDataSource(db);
    remote = FakeWalletRemoteDataSource(
      chaos: chaos,
      initialBalanceCents: serverBalanceCents,
    );
    seq = 0;
    repo = WalletRepositoryImpl(
      local: local,
      remote: remote,
      uuid: () => 'tx_${seq++}',
    );
  }

  tearDown(() => db.close());

  Future<int> available() async => (await repo.getAccount())
      .getOrElse(() => throw 'no account')
      .availableCents;

  /// Stands in for the sync worker: push each queued row, fold in the balance
  /// the server reports.
  Future<void> drainOutbox() async {
    for (final tx in await local.pendingTransactions()) {
      final ack = await remote.pushTransfer(
        idempotencyKey: tx.id,
        toCounterparty: tx.counterparty,
        amountCents: tx.amountCents,
      );
      await local.confirmTransfer(
        txId: tx.id,
        confirmedBalanceCents: ack.balanceCents,
        serverTime: ack.serverTime,
      );
    }
  }

  test('a transient failure leaves the transfer queued and still succeeds',
      () async {
    await boot(chaos: const ChaosConfig(latency: Duration.zero, offline: true));

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isRight(), isTrue);
    expect((await local.pendingTransactions()).single.status, isA<Pending>());
    expect(await available(), 240000);
  });

  test('a rejection is terminal: the row closes out and the money comes back',
      () async {
    await boot(
        chaos: const ChaosConfig(latency: Duration.zero, rejectTransfers: true));

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isLeft(), isTrue, reason: 'the user is told immediately');
    result.fold(
      (f) => expect(f, isA<RejectedFailure>()),
      (_) => fail('should not have succeeded'),
    );

    final row = (await local.getTransactions()).single;
    expect(row.status, isA<Rejected>());
    expect((row.status as Rejected).reason, 'INSUFFICIENT_FUNDS');

    expect(await local.pendingTransactions(), isEmpty,
        reason: 'never retried — it would fail identically forever');
    expect(await available(), 250000,
        reason: 'a rejected row drops out of the pending sum, '
            'so the derived balance gives the money back on its own');
  });

  test('the local balance check is optimistic, not authoritative', () async {
    // The device thinks it has 250000; the server knows better (money spent
    // on another device). The local check passes and the server still refuses.
    await boot(serverBalanceCents: 5000);

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isLeft(), isTrue);
    expect((await local.getTransactions()).single.status, isA<Rejected>());
  });

  group('the ambiguous timeout — applied by the server, never seen by the '
      'client', () {
    setUp(() => boot(
        chaos:
            const ChaosConfig(latency: Duration.zero, dropAfterApply: true)));

    test('retrying with the same key does not debit the server twice',
        () async {
      final result =
          await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

      expect(result.isRight(), isTrue);
      expect(remote.balanceCents, 240000,
          reason: 'the server DID apply it before the connection died');
      expect((await local.pendingTransactions()).single.status, isA<Pending>(),
          reason: 'the client cannot know, so its only safe move is to retry');

      // The retry. Without idempotency this is where the double-spend happens.
      remote.chaos = _instant;
      await drainOutbox();

      expect(remote.balanceCents, 240000,
          reason: 'replay returned the original outcome — no second debit');
      expect(await available(), 240000);
      expect(await local.pendingTransactions(), isEmpty);
    });

    test('the server ledger lists the transfer exactly once', () async {
      await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
      remote.chaos = _instant;
      await drainOutbox();

      final ledger = await remote.fetchTransactions();
      expect(ledger.map((t) => t.id), ['tx_0']);
    });
  });

  test('fetchTransactions reports what the server actually applied', () async {
    await boot();
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    await repo.transfer(toCounterparty: 'Bob', amountCents: 2500);

    final ledger = await remote.fetchTransactions();
    expect(ledger.map((t) => t.counterparty), ['Alice', 'Bob']);
    expect(ledger.map((t) => t.amountCents), [10000, 2500]);
  });

  test('a queued transfer is never in the server ledger', () async {
    await boot(chaos: const ChaosConfig(latency: Duration.zero, offline: true));
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    remote.chaos = _instant;
    expect(await remote.fetchTransactions(), isEmpty);
  });

  test('failureRate is reproducible when the Random is seeded', () async {
    Future<List<String>> run() async {
      final r = FakeWalletRemoteDataSource(
        chaos: const ChaosConfig(latency: Duration.zero, failureRate: 0.5),
        random: Random(42),
      );
      final outcomes = <String>[];
      for (var i = 0; i < 8; i++) {
        try {
          await r.pushTransfer(
              idempotencyKey: 'k$i', toCounterparty: 'Alice', amountCents: 1);
          outcomes.add('ok');
        } on NetworkException {
          outcomes.add('fail');
        }
      }
      return outcomes;
    }

    final first = await run();
    expect(first, contains('fail'), reason: 'chaos has to actually fire');
    expect(first, contains('ok'));
    expect(await run(), first, reason: 'a flaky-network test must not be flaky');
  });
}
