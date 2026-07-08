import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/account_model.dart';
import '../models/transaction_model.dart';

/// The local DB is the SINGLE SOURCE OF TRUTH (offline-first).
/// The UI always reads from here; the network only refreshes it.
class WalletLocalDataSource {
  WalletLocalDataSource([this._testDb]);
  final Database? _testDb;
  Database? _db;

  Future<Database> get _database async {
    if (_testDb != null) return _testDb;
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'wallet.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE account(
            id TEXT PRIMARY KEY, holder_name TEXT, balance_cents INTEGER, currency TEXT)''');
        await db.execute('''
          CREATE TABLE txn(
            id TEXT PRIMARY KEY, counterparty TEXT, amount_cents INTEGER,
            direction INTEGER, timestamp INTEGER, synced INTEGER)''');
        // Seed a demo account so the app runs out of the box (clean-room fake data).
        await db.insert('account', const {
          'id': 'acc_demo',
          'holder_name': 'Abdurrahman J. M.',
          'balance_cents': 250000,
          'currency': 'USD',
        });
      },
    );
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
    final rows = await db.query('txn', orderBy: 'timestamp DESC');
    return rows.map(TransactionModel.fromMap).toList();
  }

  Future<void> insertTransaction(TransactionModel tx) async {
    final db = await _database;
    await db.insert('txn', tx.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Applies a transfer atomically: debit balance + write txn in one DB transaction.
  Future<void> applyTransfer(AccountModel updated, TransactionModel tx) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.insert('account', updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('txn', tx.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
