import 'package:drift/drift.dart';

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  DateTimeColumn get txnDate => dateTime()();
  TextColumn get counterpartyName => text().nullable()();
  TextColumn get transferMethod => text().nullable()();
  TextColumn get referenceNo => text().nullable()();
  TextColumn get receivingNumber => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get ocrRawText => text().nullable()();
  RealColumn get ocrConfidence => real().nullable()();
  TextColumn get extractionSource => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  TextColumn get color => text().withDefault(const Constant('#64748B'))();
  TextColumn get type => text().withDefault(const Constant('both'))();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncTombstones extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text().withDefault(const Constant('transactions'))();
  DateTimeColumn get deletedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Monthly spending limit. `categoryId == null` means an overall monthly budget.
/// Stored on-device only (not synced to Supabase).
@DataClassName('Budget')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Savings goal tracked manually. Stored on-device only (not synced to Supabase).
@DataClassName('SavingsGoal')
class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get targetMinor => integer()();
  IntColumn get savedMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}
