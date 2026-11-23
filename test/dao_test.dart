import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/data/local/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  TransactionsCompanion txn(String id, {String type = 'expense', double amount = 10, String currency = 'USD', String? category}) {
    final now = DateTime(2026, 11, 21);
    return TransactionsCompanion.insert(
      id: id,
      userId: 'u1',
      type: type,
      amount: amount,
      amountMinor: Value(amountToMinorUnits(amount, currency)),
      currency: Value(currency),
      categoryId: Value(category),
      txnDate: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('DAO persists and reads a transaction by id', () async {
    await db.transactionDao.upsert(txn('t1', type: 'income', amount: 100));
    final row = await db.transactionDao.byId('t1');
    expect(row, isNotNull);
    expect(row!.preciseAmount, 100);
    expect(await db.transactionDao.getAll('u1'), hasLength(1));
    expect(await db.transactionDao.getAll('someone-else'), isEmpty);
  });

  test('three-decimal currencies keep exact minor units', () async {
    await db.transactionDao.upsert(txn('t2', amount: 1.234, currency: 'KWD'));
    expect((await db.transactionDao.byId('t2'))!.preciseAmount, 1.234);
  });

  test('delete tombstone is stored independently of the row', () async {
    await db.tombstoneDao.add('deleted-id', 'u1');
    final pending = await db.tombstoneDao.all('u1');
    expect(pending.single.id, 'deleted-id');
    expect(pending.single.entityType, 'transactions');
  });

  test('detachCategory clears the category and queues the row for sync', () async {
    await db.transactionDao.upsert(txn('t3', category: 'cat-1'));
    await db.transactionDao.markSynced('t3');
    await db.transactionDao.detachCategory('u1', 'cat-1');
    final row = (await db.transactionDao.byId('t3'))!;
    expect(row.categoryId, isNull);
    expect(row.pendingSync, isTrue);
  });

  test('budgets and goals round-trip', () async {
    final now = DateTime(2026, 11, 21);
    await db.budgetDao.upsert(BudgetsCompanion.insert(id: 'b1', userId: 'u1', amountMinor: 50000, createdAt: now));
    await db.goalDao.upsert(SavingsGoalsCompanion.insert(id: 'g1', userId: 'u1', name: 'Trip', targetMinor: 100000, createdAt: now));
    await db.goalDao.setSaved('g1', 25000);
    expect(await db.budgetDao.watchForUser('u1').first, hasLength(1));
    expect((await db.goalDao.watchForUser('u1').first).single.savedMinor, 25000);
  });
}
