import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/data/local/app_database.dart';
import 'package:ledgerlens/domain/analytics.dart';
import 'package:ledgerlens/domain/csv_export.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(String id, String type, double amount, DateTime date, {String currency = 'USD', String? category, String? name}) =>
      db.transactionDao.upsert(TransactionsCompanion.insert(
        id: id,
        userId: 'u1',
        type: type,
        amount: amount,
        amountMinor: Value(amountToMinorUnits(amount, currency)),
        currency: Value(currency),
        categoryId: Value(category),
        counterpartyName: Value(name),
        txnDate: date,
        createdAt: date,
        updatedAt: date,
      ));

  test('totals are summed per currency in exact minor units', () async {
    await add('a', 'income', 100.10, DateTime(2026, 11, 1));
    await add('b', 'income', 0.20, DateTime(2026, 11, 2));
    await add('c', 'expense', 40.05, DateTime(2026, 11, 3));
    await add('d', 'expense', 999, DateTime(2026, 11, 3), currency: 'EUR');
    final rows = await db.transactionDao.getAll('u1');
    final totals = totalsOf(inMonth(rows, DateTime(2026, 11), 'USD'), 'USD');
    expect(totals.income, 100.30);
    expect(totals.expense, 40.05);
    expect(totals.net, closeTo(60.25, 1e-9));
  });

  test('monthly trend covers the requested window', () async {
    await add('a', 'expense', 10, DateTime(2026, 9, 5));
    await add('b', 'expense', 20, DateTime(2026, 11, 5));
    final rows = await db.transactionDao.getAll('u1');
    final trend = monthlyTrend(rows, DateTime(2026, 11), 3, 'USD');
    expect(trend.map((p) => p.month.month), [9, 10, 11]);
    expect(trend.map((p) => p.expense), [10, 0, 20]);
  });

  test('budget spent respects category, currency and month', () async {
    await add('a', 'expense', 30, DateTime(2026, 11, 5), category: 'food');
    await add('b', 'expense', 70, DateTime(2026, 11, 6), category: 'fuel');
    await add('c', 'expense', 15, DateTime(2026, 10, 6), category: 'food');
    final rows = await db.transactionDao.getAll('u1');
    final now = DateTime(2026, 11, 20);
    final food = Budget(id: 'x', userId: 'u1', categoryId: 'food', amountMinor: 10000, currency: 'USD', createdAt: now);
    final overall = Budget(id: 'y', userId: 'u1', categoryId: null, amountMinor: 10000, currency: 'USD', createdAt: now);
    expect(budgetSpent(food, rows, DateTime(2026, 11)), 30);
    expect(budgetSpent(overall, rows, DateTime(2026, 11)), 100);
  });

  test('resolveCurrency prefers selection, then default, then most used', () async {
    await add('a', 'expense', 1, DateTime(2026, 11, 1), currency: 'EUR');
    await add('b', 'expense', 1, DateTime(2026, 11, 2), currency: 'EUR');
    await add('c', 'expense', 1, DateTime(2026, 11, 3), currency: 'USD');
    final rows = await db.transactionDao.getAll('u1');
    expect(resolveCurrency(rows, preferred: 'USD'), 'USD');
    expect(resolveCurrency(rows, preferred: 'SAR'), 'EUR');
    expect(resolveCurrency(rows, preferred: 'USD', selected: 'EUR'), 'EUR');
  });

  test('CSV export neutralises formula injection', () async {
    await add('a', 'expense', 5, DateTime(2026, 11, 1), name: '=HYPERLINK("http://evil")');
    final rows = await db.transactionDao.getAll('u1');
    final csv = buildTransactionsCsv(rows, const {});
    expect(csv, contains("'=HYPERLINK"));
    expect(sanitizeCsvCell('+1'), "'+1");
    expect(sanitizeCsvCell('Cafe'), 'Cafe');
  });
}
