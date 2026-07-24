import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/data/datasources/chaos_config.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:offline_first_wallet/data/models/transaction_model.dart';
import 'package:offline_first_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:offline_first_wallet/data/sync/backoff_policy.dart';
import 'package:offline_first_wallet/data/sync/sync_service.dart';
import 'package:offline_first_wallet/domain/entities/sync_status.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';

const _instant = ChaosConfig(latency: Duration.zero);
const _offline = ChaosConfig(latency: Duration.zero, offline: true);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late WalletLocalDataSource local;
  late WalletRemoteDataSource remote;
  late WalletRepositoryImpl repo;
  late SyncService sync;

  /// A clock the test drives by hand, so backoff windows can be crossed
  /// without any real waiting.
  late DateTime now;
  var seq = 0;

  Future<void> boot({
    ChaosConfig chaos = _instant,
    BackoffPolicy backoff = const BackoffPolicy(),
    Stream<bool>? onOnline,
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
      local: local,
      remote: remote,
      uuid: () => 'tx_${seq++}',
    );
    now = DateTime(2026, 1, 1, 12);
    sync = SyncService(
      local: local,
      remote: remote,
      backoff: backoff,
      onOnline: onOnline,
      clock: () => now,
      random: Random(7),
    );
  }

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  /// Queues [amountCents] with the network down.
  Future<void> queueOffline(String to, int amountCents) async {
    final before = remote.chaos;
    remote.chaos = _offline;
    await repo.transfer(toCounterparty: to, amountCents: amountCents);
    remote.chaos = before;
  }

  Future<TransactionModel> row(String id) async =>
      (await local.getTransactions()).firstWhere((t) => t.id == id);

  group('draining', () {
    test('a queued transfer reaches the server once connectivity returns',
        () async {
      await boot();
      await queueOffline('Alice', 10000);
      expect(await local.pendingCount(), 1);

      await sync.sync();

      expect(await local.pendingCount(), 0);
      expect((await row('tx_0')).status, isA<Synced>());
      expect(remote.balanceCents, 240000);
      expect((await local.getAccount())!.confirmedBalanceCents, 240000);
    });

    test('the balance does not move when the queue drains', () async {
      await boot();
      await queueOffline('Alice', 10000);
      final before = (await repo.getAccount())
          .getOrElse(() => throw 'no account')
          .availableCents;

      await sync.sync();

      final after = (await repo.getAccount())
          .getOrElse(() => throw 'no account')
          .availableCents;
      expect(after, before, reason: 'no flicker, end to end through the worker');
    });

    test('an online reconnection triggers a drain', () async {
      final online = StreamController<bool>();
      await boot(onOnline: online.stream);
      await queueOffline('Alice', 10000);
      await sync.start();
      expect(await local.pendingCount(), 0,
          reason: 'start() drains what a previous session left behind');

      await queueOffline('Bob', 5000);
      // Wait on the worker's own signal — a fixed delay would be racing the
      // several DB round-trips a drain makes.
      final drained = sync.status.firstWhere((s) => s is SyncIdle);
      online.add(true);
      await drained;

      expect(await local.pendingCount(), 0);
      await online.close();
    });
  });

  group('ordering', () {
    test('a transient failure stops the drain — later rows do not jump ahead',
        () async {
      await boot();
      await queueOffline('Alice', 10000);
      await queueOffline('Bob', 5000);

      // Alice is at the head and the network is still down for her push.
      remote.chaos = _offline;
      await sync.sync();

      expect((await row('tx_0')).status, isA<Pending>());
      expect((await row('tx_1')).status, isA<Pending>(),
          reason: 'Bob must not overtake Alice — reordering a ledger can turn '
              'a declined transfer into an accepted one');
      expect(remote.balanceCents, 250000);
    });

    test('rows drain oldest-first, not by timestamp', () async {
      await boot();
      await queueOffline('Alice', 10000);
      await queueOffline('Bob', 5000);

      await sync.sync();

      final ledger = await remote.fetchTransactions();
      expect(ledger.map((t) => t.counterparty), ['Alice', 'Bob']);
    });

    test('a rejection does not block the rows behind it', () async {
      // The server only has 12000, which the device has no way to know — its
      // own figure is the stale 250000. Alice is refused on the server's
      // balance rule; Bob is a separate transfer that still fits.
      await boot(serverBalanceCents: 12000);
      await queueOffline('Alice', 20000);
      await queueOffline('Bob', 5000);

      await sync.sync();

      expect((await row('tx_0')).status, isA<Rejected>());
      expect((await row('tx_1')).status, isA<Synced>(),
          reason: 'a dead transfer must not hold up a live one');
      expect(remote.balanceCents, 7000);
    });
  });

  group('backoff', () {
    test('a failed attempt is recorded on the row and survives a restart',
        () async {
      await boot(chaos: _offline);
      await queueOffline('Alice', 10000);

      await sync.sync();

      final pending = (await row('tx_0')).status as Pending;
      expect(pending.attempts, 1);
      expect(pending.nextAttemptAt, isNotNull);
      expect(pending.nextAttemptAt!.isAfter(now), isTrue);

      // A "restart": a brand-new service reading the same database.
      final restarted = SyncService(
        local: local,
        remote: remote,
        clock: () => now,
        random: Random(7),
      );
      addTearDown(restarted.dispose);
      await restarted.sync();

      expect((await row('tx_0')).status, isA<Pending>());
      expect(((await row('tx_0')).status as Pending).attempts, 1,
          reason: 'still cooling off — the backoff was not reset by restarting');
    });

    test('a row is not retried before its window elapses', () async {
      await boot(chaos: _offline);
      await queueOffline('Alice', 10000);
      await sync.sync();
      final scheduled = ((await row('tx_0')).status as Pending).nextAttemptAt!;

      remote.chaos = _instant;
      await sync.sync();
      expect((await row('tx_0')).status, isA<Pending>(),
          reason: 'not due yet');

      now = scheduled.add(const Duration(seconds: 1));
      await sync.sync();
      expect((await row('tx_0')).status, isA<Synced>());
    });

    test('the window grows with attempts and stays inside the cap', () async {
      const policy = BackoffPolicy(
        base: Duration(seconds: 2),
        cap: Duration(minutes: 5),
      );
      final random = Random(1);

      for (final attempt in [1, 2, 3, 10, 20]) {
        final window = policy.base.inMilliseconds * pow(2, attempt);
        final expectedCap =
            min(window, policy.cap.inMilliseconds).toInt();
        for (var i = 0; i < 50; i++) {
          final delay = policy.delayFor(attempt, random);
          expect(delay.inMilliseconds, inInclusiveRange(0, expectedCap));
        }
      }
    });

    test('jitter actually spreads retries out', () async {
      const policy = BackoffPolicy();
      final random = Random(3);
      final delays = {
        for (var i = 0; i < 20; i++) policy.delayFor(5, random).inMilliseconds,
      };
      expect(delays.length, greaterThan(10),
          reason: 'identical delays would have every device retry in unison');
    });
  });

  group('parking', () {
    test('a transfer that exhausts its retries parks the queue rather than '
        'being reversed', () async {
      await boot(
        chaos: _offline,
        backoff: const BackoffPolicy(maxAttempts: 3, base: Duration(seconds: 1)),
      );
      await queueOffline('Alice', 10000);

      for (var i = 0; i < 4; i++) {
        await sync.sync();
        now = now.add(const Duration(hours: 1)); // always past the window
      }

      expect(sync.isParked, isTrue);
      expect(sync.current, isA<SyncParked>());
      expect((sync.current as SyncParked).blockedTxId, 'tx_0');
      expect((await row('tx_0')).status, isA<Pending>(),
          reason: 'NOT reversed — a dropped reply looks like a dropped '
              'request, so the money may really have moved');
    });

    test('a parked queue does not restart on its own', () async {
      await boot(
        chaos: _offline,
        backoff: const BackoffPolicy(maxAttempts: 2, base: Duration(seconds: 1)),
      );
      await queueOffline('Alice', 10000);
      for (var i = 0; i < 3; i++) {
        await sync.sync();
        now = now.add(const Duration(hours: 1));
      }
      expect(sync.isParked, isTrue);

      remote.chaos = _instant;
      await sync.sync();
      expect((await row('tx_0')).status, isA<Pending>(),
          reason: 'needs a human, not another tick');

      await sync.resume();
      expect((await row('tx_0')).status, isA<Synced>());
    });

    test('cancelling the blocking transfer unblocks the queue', () async {
      await boot(
        chaos: _offline,
        backoff: const BackoffPolicy(maxAttempts: 2, base: Duration(seconds: 1)),
      );
      await queueOffline('Alice', 10000);
      await queueOffline('Bob', 5000);
      for (var i = 0; i < 3; i++) {
        await sync.sync();
        now = now.add(const Duration(hours: 1));
      }
      expect(sync.isParked, isTrue);

      remote.chaos = _instant;
      await sync.cancelQueued('tx_0');

      expect((await row('tx_0')).status, isA<Rejected>());
      expect((await row('tx_1')).status, isA<Synced>(),
          reason: 'Bob was only ever waiting on Alice');
      expect(await local.pendingCount(), 0);
    });

    test('a cancelled transfer gives the money back', () async {
      await boot(chaos: _offline);
      await queueOffline('Alice', 10000);
      expect(
        (await repo.getAccount()).getOrElse(() => throw '!').availableCents,
        240000,
      );

      await sync.cancelQueued('tx_0');

      expect(
        (await repo.getAccount()).getOrElse(() => throw '!').availableCents,
        250000,
        reason: 'it drops out of the pending sum, so the derived balance '
            'restores itself',
      );
    });
  });

  group('safety', () {
    test('overlapping drains do not double-push', () async {
      await boot(chaos: const ChaosConfig(latency: Duration(milliseconds: 20)));
      await queueOffline('Alice', 10000);

      await Future.wait([sync.sync(), sync.sync(), sync.sync()]);

      expect((await remote.fetchTransactions()).length, 1);
      expect(remote.balanceCents, 240000);
    });

    test('status reports what is still queued', () async {
      await boot();
      final seen = <SyncStatus>[];
      final sub = sync.status.listen(seen.add);

      await queueOffline('Alice', 10000);
      await queueOffline('Bob', 5000);
      await sync.sync();
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<SyncInProgress>().single.queued, 2);
      expect(seen.whereType<SyncIdle>().last.queued, 0);
      await sub.cancel();
    });

    test('an empty outbox is a no-op', () async {
      await boot();
      await sync.sync();

      expect(sync.current, const SyncIdle());
      expect(await remote.fetchTransactions(), isEmpty);
    });
  });

  test('a credit is not counted as money on its way out', () async {
    await boot();
    await local.insertTransaction(TransactionModel(
      id: 'refund_1',
      counterparty: 'Alice',
      amountCents: 3000,
      direction: TxDirection.credit,
      timestamp: now,
      status: const Pending(),
    ));

    final view = (await repo.getAccount()).getOrElse(() => throw '!');
    expect(view.pendingInCents, 3000);
    expect(view.pendingOutCents, 0);
    expect(view.availableCents, 253000);
  });
}
