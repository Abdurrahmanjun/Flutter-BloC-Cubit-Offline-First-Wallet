@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/data/datasources/http_wallet_remote_datasource.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:offline_first_wallet/data/sync/backoff_policy.dart';
import 'package:offline_first_wallet/data/sync/sync_service.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';

/// The client driven against the real server over real HTTP.
///
/// The in-process fake stays the workhorse for everything else — it is faster
/// and can produce failures on demand. These exist for the handful of claims
/// that only mean something across a process boundary: that the idempotency
/// key survives serialisation, that HTTP status codes are classified into the
/// right retry behaviour, and that reconciliation matches ids that made a
/// round trip through JSON.
///
///     flutter test --tags integration
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final serverDir =
      Directory('${Directory.current.path}/server').existsSync()
          ? '${Directory.current.path}/server'
          : null;

  late Process server;
  late int port;
  late HttpWalletRemoteDataSource remote;
  late WalletLocalDataSource local;
  late Database db;
  late WalletRepositoryImpl repo;
  var seq = 0;

  /// Boots the reference server on a free port and waits for it to say so.
  Future<void> startServer({Map<String, String> chaos = const {}}) async {
    port = await _freePort();
    server = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      workingDirectory: serverDir!,
      environment: {'PORT': '$port', ...chaos},
    );

    final ready = Completer<void>();
    server.stdout.transform(const SystemEncoding().decoder).listen((line) {
      if (line.contains('wallet server on') && !ready.isCompleted) {
        ready.complete();
      }
    });
    server.stderr.transform(const SystemEncoding().decoder).listen((line) {
      if (!ready.isCompleted) ready.completeError(StateError(line));
    });
    await ready.future.timeout(const Duration(seconds: 60));
  }

  Future<void> boot({Map<String, String> chaos = const {}}) async {
    await startServer(chaos: chaos);
    remote = HttpWalletRemoteDataSource(
        baseUrl: Uri.parse('http://127.0.0.1:$port'));
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await WalletLocalDataSource.createSchema(db);
    await WalletLocalDataSource.seedDemoAccount(db);
    local = WalletLocalDataSource(db);
    seq = 0;
    repo = WalletRepositoryImpl(
        local: local, remote: remote, uuid: () => 'tx_${seq++}');
  }

  tearDown(() async {
    remote.close();
    await db.close();
    server.kill();
    await server.exitCode;
  });

  test('a transfer round-trips over HTTP and settles', () async {
    await boot();

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isRight(), isTrue);
    expect((await local.getTransactions()).single.status, isA<Synced>());
    expect((await local.getAccount())!.confirmedBalanceCents, 240000);
    expect((await remote.fetchTransactions()).single.id, 'tx_0');
  }, skip: serverDir == null ? 'server/ not found' : null);

  test('the idempotency key survives serialisation — a replay does not '
      'debit twice', () async {
    await boot();

    final first = await remote.pushTransfer(
        idempotencyKey: 'tx_same', toCounterparty: 'Alice', amountCents: 10000);
    final replay = await remote.pushTransfer(
        idempotencyKey: 'tx_same', toCounterparty: 'Alice', amountCents: 10000);

    expect(first.balanceCents, 240000);
    expect(replay.balanceCents, 240000,
        reason: '200 on a replayed key must read as success, not an error');
    expect(replay.id, first.id);
    expect((await remote.fetchTransactions()).length, 1);
  }, skip: serverDir == null ? 'server/ not found' : null);

  test('a 422 is classified as terminal, not retried', () async {
    await boot(chaos: {'CHAOS_REJECT_TRANSFERS': 'true'});

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isLeft(), isTrue);
    result.fold(
      (f) => expect(f, isA<RejectedFailure>()),
      (_) => fail('should have been refused'),
    );
    final row = (await local.getTransactions()).single;
    expect(row.status, isA<Rejected>());
    expect((row.status as Rejected).reason, 'INSUFFICIENT_FUNDS');
    expect(await local.pendingCount(), 0, reason: 'never goes back in the queue');
  }, skip: serverDir == null ? 'server/ not found' : null);

  test('THE ambiguous timeout, end to end: applied server-side, reply lost, '
      'then resolved by id', () async {
    await boot(chaos: {'CHAOS_DROP_AFTER_APPLY': 'true'});

    // The server applies it and answers 503. The client cannot tell that from
    // a request that never arrived, so it keeps the transfer queued.
    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    expect(result.isRight(), isTrue);
    expect((await local.getTransactions()).single.status, isA<Pending>());

    // The server really did apply it.
    expect((await remote.fetchAccount()).confirmedBalanceCents, 240000);

    // Naive arithmetic would now show 240000 − 10000 = 230000. Reconciling by
    // id settles the row instead.
    final view = (await repo.refresh()).getOrElse(() => throw 'refresh failed');

    expect(view.confirmedCents, 240000);
    expect(view.pendingOutCents, 0);
    expect(view.availableCents, 240000);
    expect((await local.getTransactions()).single.status, isA<Synced>());
  }, skip: serverDir == null ? 'server/ not found' : null);

  test('the worker asks the server before parking a transfer it gave up on',
      () async {
    await boot(chaos: {'CHAOS_DROP_AFTER_APPLY': 'true'});
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    expect(await local.pendingCount(), 1);

    var now = DateTime(2026, 1, 1, 12);
    final sync = SyncService(
      local: local,
      remote: remote,
      backoff: const BackoffPolicy(maxAttempts: 1, base: Duration(seconds: 1)),
      clock: () => now,
      random: Random(7),
    );
    addTearDown(sync.dispose);

    // First drain burns the only attempt; the second finds it out of retries
    // and checks the ledger rather than giving up.
    await sync.sync();
    now = now.add(const Duration(hours: 1));
    await sync.sync();

    expect(sync.isParked, isFalse,
        reason: 'the server had it — no human needed');
    expect((await local.getTransactions()).single.status, isA<Synced>());
  }, skip: serverDir == null ? 'server/ not found' : null);

  test('an unreachable server is transient: the transfer stays queued',
      () async {
    await boot();
    server.kill();
    await server.exitCode;

    final result =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    expect(result.isRight(), isTrue, reason: 'still durable locally');
    expect((await local.getTransactions()).single.status, isA<Pending>());
    expect(await local.pendingCount(), 1);
  }, skip: serverDir == null ? 'server/ not found' : null);
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
