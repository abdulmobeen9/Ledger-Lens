import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Transactions, LocalCategories, SyncTombstones, Budgets, SavingsGoals],
  daos: [TransactionDao, CategoryDao, TombstoneDao, BudgetDao, GoalDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Created from the current table definition, which already has entity_type.
            await m.createTable(syncTombstones);
          } else if (from < 3) {
            await m.addColumn(syncTombstones, syncTombstones.entityType);
          }
          if (from < 4) await m.addColumn(localCategories, localCategories.pendingSync);
          if (from < 5) {
            await m.addColumn(transactions, transactions.amountMinor);
            await customStatement(
              "UPDATE transactions SET amount_minor = CAST(ROUND(amount * CASE WHEN currency IN ('BHD','IQD','JOD','KWD','LYD','OMR','TND') THEN 1000 WHEN currency IN ('JPY','KRW','CLP','VND') THEN 1 ELSE 100 END) AS INTEGER)",
            );
          }
          if (from < 6) {
            await m.createTable(budgets);
            await m.createTable(savingsGoals);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(File(p.join(dir.path, 'ledgerlens.sqlite')));
    });

@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase> with _$TransactionDaoMixin {
  TransactionDao(super.db);

  Stream<List<Transaction>> watchAll(String uid) => (select(transactions)
        ..where((t) => t.userId.equals(uid))
        ..orderBy([(t) => OrderingTerm.desc(t.txnDate), (t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();

  Future<List<Transaction>> getAll(String uid) => (select(transactions)
        ..where((t) => t.userId.equals(uid))
        ..orderBy([(t) => OrderingTerm.desc(t.txnDate)]))
      .get();

  Future<Transaction?> byId(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Transaction?> watchById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(TransactionsCompanion row) => into(transactions).insertOnConflictUpdate(row);

  Future<int> remove(String id) => (delete(transactions)..where((t) => t.id.equals(id))).go();

  Future<List<Transaction>> pending(String uid) =>
      (select(transactions)..where((t) => t.userId.equals(uid) & t.pendingSync.equals(true))).get();

  /// Clears a deleted category from local transactions and queues them for sync,
  /// so the server never receives a reference to a category that no longer exists.
  Future<int> detachCategory(String uid, String categoryId) =>
      (update(transactions)..where((t) => t.userId.equals(uid) & t.categoryId.equals(categoryId))).write(
        TransactionsCompanion(
          categoryId: const Value(null),
          pendingSync: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> markSynced(String id, {DateTime? serverUpdatedAt}) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          pendingSync: const Value(false),
          updatedAt: serverUpdatedAt == null ? const Value.absent() : Value(serverUpdatedAt),
        ),
      );
}

@DriftAccessor(tables: [LocalCategories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<LocalCategory>> watchForUser(String uid) => (select(localCategories)
        ..where((c) => c.userId.equals(uid))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();

  Future<List<LocalCategory>> getForUser(String uid) => (select(localCategories)
        ..where((c) => c.userId.equals(uid))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .get();

  Future<void> upsert(LocalCategoriesCompanion row) => into(localCategories).insertOnConflictUpdate(row);

  Future<List<LocalCategory>> pending(String uid) =>
      (select(localCategories)..where((c) => c.userId.equals(uid) & c.pendingSync.equals(true))).get();

  Future<void> markSynced(String id) => (update(localCategories)..where((c) => c.id.equals(id)))
      .write(const LocalCategoriesCompanion(pendingSync: Value(false)));

  Future<int> deleteById(String id) => (delete(localCategories)..where((c) => c.id.equals(id))).go();
}

@DriftAccessor(tables: [SyncTombstones])
class TombstoneDao extends DatabaseAccessor<AppDatabase> with _$TombstoneDaoMixin {
  TombstoneDao(super.db);

  Future<void> add(String id, String uid, {String entityType = 'transactions'}) =>
      into(syncTombstones).insertOnConflictUpdate(SyncTombstonesCompanion.insert(
        id: id,
        userId: uid,
        entityType: Value(entityType),
        deletedAt: DateTime.now(),
      ));

  Future<List<SyncTombstone>> all(String uid) =>
      (select(syncTombstones)..where((t) => t.userId.equals(uid))).get();

  Future<void> remove(String id) => (delete(syncTombstones)..where((t) => t.id.equals(id))).go();
}

@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<List<Budget>> watchForUser(String uid) => (select(budgets)
        ..where((b) => b.userId.equals(uid))
        ..orderBy([(b) => OrderingTerm.asc(b.createdAt)]))
      .watch();

  Future<void> upsert(BudgetsCompanion row) => into(budgets).insertOnConflictUpdate(row);

  Future<int> deleteById(String id) => (delete(budgets)..where((b) => b.id.equals(id))).go();

  Future<int> deleteForCategory(String uid, String categoryId) =>
      (delete(budgets)..where((b) => b.userId.equals(uid) & b.categoryId.equals(categoryId))).go();
}

@DriftAccessor(tables: [SavingsGoals])
class GoalDao extends DatabaseAccessor<AppDatabase> with _$GoalDaoMixin {
  GoalDao(super.db);

  Stream<List<SavingsGoal>> watchForUser(String uid) => (select(savingsGoals)
        ..where((g) => g.userId.equals(uid))
        ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
      .watch();

  Future<void> upsert(SavingsGoalsCompanion row) => into(savingsGoals).insertOnConflictUpdate(row);

  Future<void> setSaved(String id, int savedMinor) => (update(savingsGoals)..where((g) => g.id.equals(id)))
      .write(SavingsGoalsCompanion(savedMinor: Value(savedMinor)));

  Future<int> deleteById(String id) => (delete(savingsGoals)..where((g) => g.id.equals(id))).go();
}

int currencyMinorUnitFactor(String currency) {
  final code = currency.toUpperCase();
  if (const {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'}.contains(code)) return 1000;
  if (const {'JPY', 'KRW', 'CLP', 'VND'}.contains(code)) return 1;
  return 100;
}

int amountToMinorUnits(double amount, String currency) => (amount * currencyMinorUnitFactor(currency)).round();

double minorUnitsToAmount(int minor, String currency) => minor / currencyMinorUnitFactor(currency);

extension TransactionMoney on Transaction {
  double get preciseAmount => amountMinor / currencyMinorUnitFactor(currency);
}
