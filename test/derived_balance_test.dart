import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/core/error/exceptions.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:offline_first_wallet/data/models/account_model.dart';
import 'package:offline_first_wallet/data/models/transfer_ack.dart';
import 'package:offline_first_wallet/data/repositories/wallet_repository_impl.dart';

/// A remote that can be taken offline mid-test — the minimum needed to reach
/// the queued path.
class _FakeRemote extends WalletRemoteDataSource {
  bool offline = false;

  @override
  Future<AccountModel> fetchAccount() {
    if (offline) throw const NetworkException();
    return super.fetchAccount();
  }

  @override
  Future<TransferAck> pushTransfer({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  }) {
    if (offline) throw const NetworkException();
    return super.pushTransfer(
      idempotencyKey: idempotencyKey,
      toCounterparty: toCounterparty,
      amountCents: amountCents,
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late WalletLocalDataSource local;
  late _FakeRemote remote;
  late WalletRepositoryImpl repo;
  var seq = 0;

  // `:memory:` is shared between handles unless singleInstance is off, which
  // would otherwise leak one test's schema into the next.
  Future<Database> freshDb() => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );

  setUp(() async {
    db = await freshDb();
    await WalletLocalDataSource.createSchema(db);
    await WalletLocalDataSource.seedDemoAccount(db);
    local = WalletLocalDataSource(db);
    remote = _FakeRemote();
    seq = 0;
    repo = WalletRepositoryImpl(
      local: local,
      remote: remote,
      uuid: () => 'tx_${seq++}',
    );
  });

  tearDown(() => db.close());

  Future<int> available() async =>
      (await repo.getAccount()).getOrElse(() => throw 'no account').availableCents;

  /// Stands in for the sync worker: drain the outbox, push each row, fold the
  /// server's reported balance into the confirmed one.
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
      );
    }
  }

  test('THE no-flicker property: balance is identical before and after a '
      'queued transfer syncs', () async {
    remote.offline = true;
    final result = await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);
    expect(result.isRight(), isTrue, reason: 'offline transfer still succeeds locally');

    final whileQueued = await available();
    expect(whileQueued, 240000, reason: 'the debit shows immediately');

    remote.offline = false;
    await drainOutbox();

    expect(await available(), whileQueued,
        reason: 'syncing must not move the number the user is looking at');
  });

  test('a queued debit never touches the confirmed balance', () async {
    remote.offline = true;
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    final view = (await repo.getAccount()).getOrElse(() => throw 'no account');
    expect(view.confirmedCents, 250000, reason: 'server has not seen it yet');
    expect(view.pendingOutCents, 10000);
    expect(view.availableCents, 240000);
    expect(view.hasPending, isTrue);
  });

  test('cannot overdraw while offline: queued debits accumulate against the '
      'available figure', () async {
    remote.offline = true;
    for (var i = 0; i < 2; i++) {
      final r = await repo.transfer(toCounterparty: 'Alice', amountCents: 100000);
      expect(r.isRight(), isTrue);
    }
    expect(await available(), 50000);

    // Third one exceeds what's left, even though `confirmed` is still 250000.
    final third =
        await repo.transfer(toCounterparty: 'Alice', amountCents: 100000);
    expect(third.isLeft(), isTrue);
    third.fold(
      (f) => expect(f, isA<TransferFailure>()),
      (_) => fail('should have been rejected'),
    );
    expect(await available(), 50000, reason: 'rejection changes nothing');
  });

  test('an online transfer confirms straight away — nothing left queued',
      () async {
    await repo.transfer(toCounterparty: 'Alice', amountCents: 10000);

    final view = (await repo.getAccount()).getOrElse(() => throw 'no account');
    expect(view.pendingOutCents, 0);
    expect(view.confirmedCents, 240000, reason: 'folded into the server figure');
    expect(view.availableCents, 240000);
    expect(await local.pendingTransactions(), isEmpty);
  });

  test('replaying an idempotency key does not debit the server twice',
      () async {
    final ack1 = await remote.pushTransfer(
        idempotencyKey: 'tx_same', toCounterparty: 'Alice', amountCents: 10000);
    final ack2 = await remote.pushTransfer(
        idempotencyKey: 'tx_same', toCounterparty: 'Alice', amountCents: 10000);

    expect(ack1.balanceCents, 240000);
    expect(ack2.balanceCents, 240000, reason: 'replay returns the first outcome');
  });

  test('v1 → v2 migration preserves the balance under its new meaning',
      () async {
    final old = await freshDb();
    await old.execute('''
      CREATE TABLE account(
        id TEXT PRIMARY KEY, holder_name TEXT, balance_cents INTEGER, currency TEXT)''');
    await old.insert('account', {
      'id': 'acc_demo',
      'holder_name': 'Jamie Carter',
      'balance_cents': 191500,
      'currency': 'USD',
    });

    await WalletLocalDataSource.migrate(old, 1, WalletLocalDataSource.schemaVersion);

    final rows = await old.query('account');
    expect(AccountModel.fromMap(rows.first).confirmedBalanceCents, 191500);
    await old.close();
  });
}
