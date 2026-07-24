import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/data/datasources/chaos_config.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:offline_first_wallet/data/models/account_model.dart';
import 'package:offline_first_wallet/data/models/remote_transaction.dart';
import 'package:offline_first_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:offline_first_wallet/data/sync/backoff_policy.dart';
import 'package:offline_first_wallet/data/sync/sync_service.dart';
import 'package:offline_first_wallet/data/sync/sync_status.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';

const _instant = ChaosConfig(latency: Duration.zero);
const _offline = ChaosConfig(latency: Duration.zero, offline: true);
const _dropAfterApply =
    ChaosConfig(latency: Duration.zero, dropAfterApply: true);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late WalletLocalDataSource local;
  late WalletRemoteDataSource remote;
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
    remote = WalletRemoteDataSource(
        chaos: chaos, initialBalanceCents: serverBalanceCents);
    seq = 0;
    repo = WalletRepositoryImpl(
      local: local, remote: remote, uuid: () => 'tx_${seq++}');
  }

  setUp(boot);
  tearDown(() => db.close());

  Future<int> available() async => (await repo.getAccount())
      .getOrElse(() => throw 'no account')
      .availableCents;

  Future<void> queueOffline(String to, int cents) async {
    final before = remote.chaos;
    remote.chaos = _offline;
    await repo.transfer(toCounterparty: to, amountCents: cents);
    remote.chaos = before;
  }

  test('THE double-count trap: a transfer the server already applied is '
      'promoted, not subtracted a second time', () async {
    // The server applies it, then the connection dies. The client is left
    // holding a pending row for a transfer that already happened.
    remote.chaos = _dropAfterApply;
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    remote.chaos = _instant;

    expect(remote.balanceCents, 240000, reason: 'the server did apply it');
    expect(await local.pendingCount(), 1, reason: 'the client cannot know');

    // Naive arithmetic here would be 240000 (server) − 10000 (still "pending")
    // = 230000, and the user would be shown money that does not exist.
    final view = (await repo.refresh()).getOrElse(() => throw 'refresh failed');

    expect(view.confirmedCents, 240000);
    expect(view.pendingOutCents, 0, reason: 'settled by id, not by arithmetic');
    expect(view.availableCents, 240000);
    expect(await local.pendingCount(), 0);
  });

  test('a genuinely queued transfer stays pending across a refresh', () async {
    await queueOffline('Alice', 10000);

    final view = (await repo.refresh()).getOrElse(() => throw 'refresh failed');

    expect(view.confirmedCents, 250000, reason: 'the server never saw it');
    expect(view.pendingOutCents, 10000);
    expect(view.availableCents, 240000);
  });

  test('the balance does not flicker across a refresh', () async {
    await queueOffline('Alice', 10000);
    final before = await available();

    await repo.refresh();

    expect(await available(), before);
  });

  test('a transfer made on another device appears in the history', () async {
    // Applied server-side with a key this device has never used.
    await remote.pushTransfer(
        idempotencyKey: 'tx_from_tablet',
        toCounterparty: 'Dana',
        amountCents: 4000);

    final view = (await repo.refresh()).getOrElse(() => throw 'refresh failed');

    final rows = await local.getTransactions();
    expect(rows.single.id, 'tx_from_tablet');
    expect(rows.single.status, isA<Synced>(),
        reason: 'already inside the server balance — it must not be re-queued');
    expect(view.availableCents, 246000);
    expect(await local.pendingCount(), 0);
  });

  test('refreshing twice does not duplicate anything', () async {
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    await repo.refresh();
    await repo.refresh();

    expect((await local.getTransactions()).length, 1);
    expect(await available(), 240000);
  });

  test('the server ledger overrules a transfer this device gave up on',
      () async {
    // Applied by the server, then cancelled locally by an impatient user.
    remote.chaos = _dropAfterApply;
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    remote.chaos = _instant;
    await local.markRejected(txId: 'tx_0', reason: 'Cancelled');
    expect((await local.getTransactions()).single.status, isA<Rejected>());

    await repo.refresh();

    expect((await local.getTransactions()).single.status, isA<Synced>(),
        reason: 'the server is the authority on what actually happened');
    expect(await available(), 240000);
  });

  test('an offline refresh fails without touching the cached view', () async {
    await queueOffline('Alice', 10000);
    final before = await available();

    remote.chaos = _offline;
    final result = await repo.refresh();

    expect(result.isLeft(), isTrue);
    result.fold(
      (f) => expect(f, isA<NetworkFailure>()),
      (_) => fail('should not have succeeded'),
    );
    expect(await available(), before, reason: 'the local DB is still valid');
    expect(await local.pendingCount(), 1);
  });

  test('reconcile is atomic: promotion and the new balance land together',
      () async {
    await queueOffline('Alice', 10000);

    await local.reconcile(
      serverTransactions: [
        RemoteTransaction(
          id: 'tx_0',
          counterparty: 'Alice',
          amountCents: 10000,
          serverTime: DateTime(2026, 1, 1, 9),
        ),
      ],
      account: const AccountModel(
        id: 'acc_demo',
        holderName: 'Jamie Carter',
        confirmedBalanceCents: 240000,
        currency: 'USD',
      ),
    );

    final row = (await local.getTransactions()).single;
    expect(row.status, isA<Synced>());
    expect((row.status as Synced).serverTime, DateTime(2026, 1, 1, 9));
    expect((await local.getAccount())!.confirmedBalanceCents, 240000);
    expect(await available(), 240000);
  });

  group('the worker asks the server before giving up', () {
    test('a transfer that actually landed is resolved instead of parking',
        () async {
      // Applied server-side, reply lost — then the network stays down long
      // enough for the worker to run out of retries.
      remote.chaos = _dropAfterApply;
      await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
      remote.chaos = _offline;

      var now = DateTime(2026, 1, 1, 12);
      final sync = SyncService(
        local: local,
        remote: remote,
        backoff:
            const BackoffPolicy(maxAttempts: 2, base: Duration(seconds: 1)),
        clock: () => now,
        random: Random(7),
      );
      addTearDown(sync.dispose);

      for (var i = 0; i < 2; i++) {
        await sync.sync();
        now = now.add(const Duration(hours: 1));
      }

      // Out of retries — but now the network is back, so the ledger can answer.
      remote.chaos = _instant;
      await sync.sync();

      expect(sync.isParked, isFalse,
          reason: 'the server had it all along — no human needed');
      expect((await local.getTransactions()).single.status, isA<Synced>());
      expect(await local.pendingCount(), 0);
      expect(await available(), 240000);
    });

    test('a transfer the server never got still parks the queue', () async {
      await queueOffline('Alice', 10000);
      remote.chaos = _offline;

      var now = DateTime(2026, 1, 1, 12);
      final sync = SyncService(
        local: local,
        remote: remote,
        backoff:
            const BackoffPolicy(maxAttempts: 2, base: Duration(seconds: 1)),
        clock: () => now,
        random: Random(7),
      );
      addTearDown(sync.dispose);

      for (var i = 0; i < 3; i++) {
        await sync.sync();
        now = now.add(const Duration(hours: 1));
      }

      expect(sync.isParked, isTrue);
      expect(sync.current, isA<SyncParked>());
      expect((await local.getTransactions()).single.status, isA<Pending>(),
          reason: 'never reversed on a guess');
    });
  });

  test('a credit on the server reconciles as a credit', () async {
    await local.reconcile(
      serverTransactions: [
        RemoteTransaction(
          id: 'refund_1',
          counterparty: 'Alice',
          amountCents: 3000,
          serverTime: DateTime(2026, 1, 1, 9),
          direction: TxDirection.credit,
        ),
      ],
      account: const AccountModel(
        id: 'acc_demo',
        holderName: 'Jamie Carter',
        confirmedBalanceCents: 253000,
        currency: 'USD',
      ),
    );

    final row = (await local.getTransactions()).single;
    expect(row.direction, TxDirection.credit);
    expect(await available(), 253000);
  });
}
