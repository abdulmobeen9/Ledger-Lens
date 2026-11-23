import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/data/local/app_database.dart';
import 'package:ledgerlens/domain/duplicates.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<Transaction>> saved() => db.transactionDao.getAll('u1');

  Future<void> add(String id, {double amount = 100, String currency = 'SAR', String? reference, String? name, String? receiving, String? notes, DateTime? date}) {
    final when = date ?? DateTime(2025, 3, 1);
    return db.transactionDao.upsert(TransactionsCompanion.insert(
      id: id,
      userId: 'u1',
      type: 'expense',
      amount: amount,
      amountMinor: Value(amountToMinorUnits(amount, currency)),
      currency: Value(currency),
      referenceNo: Value(reference),
      counterpartyName: Value(name),
      receivingNumber: Value(receiving),
      notes: Value(notes),
      txnDate: when,
      createdAt: when,
      updatedAt: when,
    ));
  }

  test('same reference number is an exact duplicate, ignoring case and spacing', () async {
    await add('a', reference: 'FT25060898016591');
    final match = findDuplicate(await saved(), reference: ' ft2506 0898016591 ');
    expect(match, isNotNull);
    expect(match!.exact, isTrue);
    expect(match.transaction.id, 'a');
  });

  test('same transfer code inside the saved notes is an exact duplicate', () async {
    await add('a', notes: 'Fee: SAR 17.25 • Transfer code: 4305707068');
    final match = findDuplicate(await saved(), transferCode: '4305707068');
    expect(match?.exact, isTrue);
  });

  test('same amount, date and name is only a possible duplicate', () async {
    await add('a', amount: 7502, name: 'Md Haroon Rain');
    final match = findDuplicate(await saved(), amount: 7502, currency: 'SAR', date: DateTime(2025, 3, 1), name: 'md haroon rain');
    expect(match, isNotNull);
    expect(match!.exact, isFalse);
  });

  test('different name, day, currency or no identifier does not match', () async {
    await add('a', amount: 7502, name: 'Md Haroon Rain');
    final rows = await saved();
    expect(findDuplicate(rows, amount: 7502, currency: 'SAR', date: DateTime(2025, 3, 1), name: 'Someone Else'), isNull);
    expect(findDuplicate(rows, amount: 7502, currency: 'SAR', date: DateTime(2025, 3, 2), name: 'Md Haroon Rain'), isNull);
    expect(findDuplicate(rows, amount: 7502, currency: 'NPR', date: DateTime(2025, 3, 1), name: 'Md Haroon Rain'), isNull);
    expect(findDuplicate(rows, amount: 7502, currency: 'SAR', date: DateTime(2025, 3, 1)), isNull);
  });

  test('the transaction being edited is never reported as its own duplicate', () async {
    await add('a', reference: 'FT25060898016591');
    expect(findDuplicate(await saved(), reference: 'FT25060898016591', excludeId: 'a'), isNull);
  });
}
