import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_first_wallet/data/datasources/wallet_local_datasource.dart';
import 'package:offline_first_wallet/data/models/transaction_model.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> freshDb() => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );

  TransactionModel txWith(TxStatus status) => TransactionModel(
        id: 't1',
        counterparty: 'Alice',
        amountCents: 10000,
        direction: TxDirection.debit,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: status,
      );

  group('status survives a round-trip through SQLite', () {
    late Database db;
    late WalletLocalDataSource local;

    setUp(() async {
      db = await freshDb();
      await WalletLocalDataSource.createSchema(db);
      await WalletLocalDataSource.seedDemoAccount(db);
      local = WalletLocalDataSource(db);
    });

    tearDown(() => db.close());

    Future<TxStatus> roundTrip(TxStatus status) async {
      await local.insertTransaction(txWith(status));
      final rows = await local.getTransactions();
      return rows.single.status;
    }

    test('Pending keeps its backoff bookkeeping', () async {
      final due = DateTime.fromMillisecondsSinceEpoch(1700000500000);
      final read = await roundTrip(Pending(attempts: 3, nextAttemptAt: due));

      expect(read, isA<Pending>());
      expect((read as Pending).attempts, 3);
      expect(read.nextAttemptAt, due);
    });

    test('Synced keeps the server time', () async {
      final serverTime = DateTime.fromMillisecondsSinceEpoch(1700000900000);
      final read = await roundTrip(Synced(serverTime: serverTime));

      expect(read, isA<Synced>());
      expect((read as Synced).serverTime, serverTime);
    });

    test('Rejected keeps the reason', () async {
      final read = await roundTrip(const Rejected('INSUFFICIENT_FUNDS'));

      expect(read, isA<Rejected>());
      expect((read as Rejected).reason, 'INSUFFICIENT_FUNDS');
    });

    test('changing status clears the previous variant\'s payload', () async {
      final due = DateTime.fromMillisecondsSinceEpoch(1700000500000);
      await local.insertTransaction(
          txWith(Pending(attempts: 5, nextAttemptAt: due)));

      await local.updateTransaction(
          txWith(const Rejected('INSUFFICIENT_FUNDS')));

      // Read the raw row: a stale next_attempt_at would make a dead transfer
      // look like it were still waiting its turn in the outbox.
      final raw = (await db.query('txn')).single;
      expect(raw['next_attempt_at'], isNull);
      expect(raw['attempts'], 0);
      expect(raw['last_error'], 'INSUFFICIENT_FUNDS');
    });

    test('only Pending rows count toward the outbox and the pending sum',
        () async {
      await local.insertTransaction(txWith(const Pending()));
      await local.insertTransaction(TransactionModel(
        id: 't2',
        counterparty: 'Bob',
        amountCents: 5000,
        direction: TxDirection.debit,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: const Rejected('INSUFFICIENT_FUNDS'),
      ));
      await local.insertTransaction(TransactionModel(
        id: 't3',
        counterparty: 'Carol',
        amountCents: 7000,
        direction: TxDirection.debit,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: const Synced(),
      ));

      expect((await local.pendingTransactions()).map((t) => t.id), ['t1']);
      expect(await local.pendingOutCents(), 10000,
          reason: 'a rejected transfer is not money on its way out');
    });

    test('confirmTransfer clears retry state and stamps the server time',
        () async {
      final due = DateTime.fromMillisecondsSinceEpoch(1700000500000);
      await local.insertTransaction(
          txWith(Pending(attempts: 4, nextAttemptAt: due)));

      final serverTime = DateTime.fromMillisecondsSinceEpoch(1700009000000);
      await local.confirmTransfer(
        txId: 't1',
        confirmedBalanceCents: 240000,
        serverTime: serverTime,
      );

      final read = (await local.getTransactions()).single;
      expect(read.status, Synced(serverTime: serverTime));
      expect(read.displayTime, serverTime,
          reason: 'server clock wins once it exists');
      expect((await local.getAccount())!.confirmedBalanceCents, 240000);
    });
  });

  test('v2 → v3 migration carries the old bool over as pending/synced',
      () async {
    final old = await freshDb();
    await old.execute('''
      CREATE TABLE txn(
        id TEXT PRIMARY KEY, counterparty TEXT, amount_cents INTEGER,
        direction INTEGER, timestamp INTEGER, synced INTEGER)''');
    for (final (id, synced) in [('old_queued', 0), ('old_done', 1)]) {
      await old.insert('txn', {
        'id': id,
        'counterparty': 'Alice',
        'amount_cents': 10000,
        'direction': TxDirection.debit.index,
        'timestamp': 1700000000000,
        'synced': synced,
      });
    }

    await WalletLocalDataSource.migrate(
        old, 2, WalletLocalDataSource.schemaVersion);

    final byId = {
      for (final row in await old.query('txn'))
        row['id'] as String: TransactionModel.fromMap(row),
    };
    expect(byId['old_queued']!.status, isA<Pending>(),
        reason: 'synced = 0 was "not sent yet"');
    expect(byId['old_done']!.status, isA<Synced>());
    expect((byId['old_queued']!.status as Pending).attempts, 0,
        reason: 'migrated rows start their backoff fresh');
    await old.close();
  });
}
