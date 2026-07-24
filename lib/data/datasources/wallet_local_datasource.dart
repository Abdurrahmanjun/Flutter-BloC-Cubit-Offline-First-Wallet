import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../../domain/entities/transaction.dart';

/// The local DB is the SINGLE SOURCE OF TRUTH (offline-first).
/// The UI always reads from here; the network only refreshes it.
///
/// Two invariants hold across this file:
///  * `account.confirmed_balance_cents` is written ONLY from a server
///    response. A local transfer never touches it.
///  * An unsynced transfer lives in `txn` as an outbox row. The spendable
///    balance is derived from confirmed − pending, never stored.
class WalletLocalDataSource {
  WalletLocalDataSource([this._testDb]);
  final Database? _testDb;
  Database? _db;

  /// Schema version. v2 split the stored balance into a server-confirmed
  /// figure and a derived one; v3 replaced the `synced` bool with a three-way
  /// status plus its retry bookkeeping — see [migrate].
  static const schemaVersion = 3;

  Future<Database> get _database async {
    if (_testDb != null) return _testDb;
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'wallet.db'),
      version: schemaVersion,
      onCreate: (db, version) async {
        await createSchema(db);
        await seedDemoAccount(db);
      },
      onUpgrade: migrate,
    );
  }

  /// Fresh installs get the current schema directly.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE account(
        id TEXT PRIMARY KEY, holder_name TEXT,
        confirmed_balance_cents INTEGER, currency TEXT)''');
    await db.execute('''
      CREATE TABLE txn(
        id TEXT PRIMARY KEY, counterparty TEXT, amount_cents INTEGER,
        direction INTEGER, timestamp INTEGER,
        status INTEGER NOT NULL DEFAULT 0,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER,
        last_error TEXT,
        reverses_id TEXT,
        server_timestamp INTEGER)''');
    // The outbox drain filters on status and orders by rowid; without this it
    // is a full scan of the whole history on every sync tick.
    await db.execute('CREATE INDEX idx_txn_status ON txn(status)');
  }

  /// Seeds a demo account so the app runs out of the box (clean-room fake data).
  static Future<void> seedDemoAccount(Database db) async {
    await db.insert('account', const {
      'id': 'acc_demo',
      'holder_name': 'Jamie Carter',
      'confirmed_balance_cents': 250000,
      'currency': 'USD',
    });
  }

  /// Public so a test can drive it against a hand-built v1 database — a
  /// migration that has never been run against real old data is a guess.
  static Future<void> migrate(Database db, int from, int to) async {
    // v1 → v2: `balance_cents` was mutated by local transfers. It now means
    // "what the server confirmed", so the rename is the whole migration —
    // existing values are already correct under the new meaning for any row
    // whose transfers had all synced.
    if (from < 2) {
      await db.execute(
        'ALTER TABLE account RENAME COLUMN balance_cents TO confirmed_balance_cents',
      );
    }

    // v2 → v3: `synced` became a three-way status. The old bool's values
    // already line up (0 = pending, 1 = synced), so existing rows carry over
    // untouched and only the new payload columns need adding.
    if (from < 3) {
      await db.execute('ALTER TABLE txn RENAME COLUMN synced TO status');
      await db.execute(
          'ALTER TABLE txn ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE txn ADD COLUMN next_attempt_at INTEGER');
      await db.execute('ALTER TABLE txn ADD COLUMN last_error TEXT');
      await db.execute('ALTER TABLE txn ADD COLUMN reverses_id TEXT');
      await db.execute('ALTER TABLE txn ADD COLUMN server_timestamp INTEGER');
      await db.execute('CREATE INDEX idx_txn_status ON txn(status)');
    }
  }

  Future<AccountModel?> getAccount() async {
    final db = await _database;
    final rows = await db.query('account', limit: 1);
    return rows.isEmpty ? null : AccountModel.fromMap(rows.first);
  }

  Future<void> upsertAccount(AccountModel account) async {
    final db = await _database;
    await db.insert('account', account.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TransactionModel>> getTransactions() async {
    final db = await _database;
    // Display order. Queue order is `rowid ASC` — see [pendingTransactions].
    final rows = await db.query('txn', orderBy: 'timestamp DESC');
    return rows.map(TransactionModel.fromMap).toList();
  }

  /// The server refused [txId] outright. No balance write is needed: a
  /// rejected row drops out of the pending sum, so the derived balance gives
  /// the money back on its own. The compensating ledger entry is a separate
  /// concern — this only records the verdict.
  Future<void> markRejected({
    required String txId,
    required String reason,
  }) async {
    final db = await _database;
    await db.update(
      'txn',
      {
        'status': TxStatusCode.rejected,
        'last_error': reason,
        'attempts': 0,
        'next_attempt_at': null,
      },
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Overwrites a row with the given status and payload.
  Future<void> updateTransaction(TransactionModel tx) async {
    final db = await _database;
    await db.update('txn', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }

  Future<void> insertTransaction(TransactionModel tx) async {
    final db = await _database;
    await db.insert('txn', tx.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Writes a transfer into the outbox. Deliberately does NOT touch the
  /// account row: the debit shows up via [pendingOutCents] until the server
  /// confirms it, at which point [confirmTransfer] folds it into the
  /// confirmed balance in one step.
  Future<void> enqueueTransfer(TransactionModel tx) => insertTransaction(tx);

  /// The outbox, in true insertion order. `rowid` is used rather than
  /// `timestamp` because device clocks lie — and a wallet must not reorder.
  Future<List<TransactionModel>> pendingTransactions() async {
    final db = await _database;
    final rows = await db.query('txn',
        where: 'status = ?',
        whereArgs: [TxStatusCode.pending],
        orderBy: 'rowid ASC');
    return rows.map(TransactionModel.fromMap).toList();
  }

  Future<int> pendingOutCents() =>
      _pendingSum(TxDirection.debit);

  Future<int> pendingInCents() =>
      _pendingSum(TxDirection.credit);

  Future<int> _pendingSum(TxDirection direction) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_cents), 0) AS total '
      'FROM txn WHERE status = ? AND direction = ?',
      [TxStatusCode.pending, direction.index],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  /// The server accepted [txId]. Marking it synced and writing the balance the
  /// server reported must happen together: between the two writes the derived
  /// balance would be wrong in one direction or the other, and a crash in the
  /// gap would leave it wrong permanently.
  Future<void> confirmTransfer({
    required String txId,
    required int confirmedBalanceCents,
    DateTime? serverTime,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'txn',
        {
          'status': TxStatusCode.synced,
          'server_timestamp': serverTime?.millisecondsSinceEpoch,
          // Retry bookkeeping is dead once confirmed; leaving it would make a
          // synced row look like it were mid-backoff.
          'attempts': 0,
          'next_attempt_at': null,
        },
        where: 'id = ?',
        whereArgs: [txId],
      );
      await txn.update(
          'account', {'confirmed_balance_cents': confirmedBalanceCents});
    });
  }
}
