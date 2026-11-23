import '../data/local/app_database.dart';

const String kUncategorized = 'uncategorized';

class Totals {
  const Totals(this.income, this.expense);
  final double income, expense;
  double get net => income - expense;
  double get savingsRate => income <= 0 ? 0 : ((income - expense) / income).clamp(-1.0, 1.0).toDouble();
}

class MonthPoint {
  const MonthPoint(this.month, this.income, this.expense);
  final DateTime month;
  final double income, expense;
  double get net => income - expense;
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

/// Sums exact minor units, then converts once, to avoid accumulating floating-point error.
/// Callers must pass rows of a single currency.
Totals totalsOf(Iterable<Transaction> rows, String currency) {
  var income = 0;
  var expense = 0;
  for (final r in rows) {
    if (r.type == 'income') {
      income += r.amountMinor;
    } else if (r.type == 'expense') {
      expense += r.amountMinor;
    }
  }
  final factor = currencyMinorUnitFactor(currency);
  return Totals(income / factor, expense / factor);
}

List<Transaction> inMonth(Iterable<Transaction> rows, DateTime month, String currency) =>
    rows.where((r) => r.currency == currency && sameMonth(r.txnDate, month)).toList();

List<MonthPoint> monthlyTrend(Iterable<Transaction> rows, DateTime endMonth, int months, String currency) {
  final points = <MonthPoint>[];
  for (var i = months - 1; i >= 0; i--) {
    final m = DateTime(endMonth.year, endMonth.month - i);
    final totals = totalsOf(inMonth(rows, m, currency), currency);
    points.add(MonthPoint(m, totals.income, totals.expense));
  }
  return points;
}

/// Expense total per category id (uncategorized rows grouped under [kUncategorized]), in minor-unit-exact sums.
Map<String, double> expenseByCategory(Iterable<Transaction> rows, String currency) {
  final minor = <String, int>{};
  for (final r in rows) {
    if (r.type != 'expense' || r.currency != currency) continue;
    final key = r.categoryId ?? kUncategorized;
    minor[key] = (minor[key] ?? 0) + r.amountMinor;
  }
  final factor = currencyMinorUnitFactor(currency);
  return minor.map((k, v) => MapEntry(k, v / factor));
}

Map<String, double> sumByLabel(Iterable<Transaction> rows, String currency, String type, String? Function(Transaction) label) {
  final minor = <String, int>{};
  for (final r in rows) {
    if (r.type != type || r.currency != currency) continue;
    final key = label(r);
    if (key == null || key.trim().isEmpty) continue;
    minor[key] = (minor[key] ?? 0) + r.amountMinor;
  }
  final factor = currencyMinorUnitFactor(currency);
  return minor.map((k, v) => MapEntry(k, v / factor));
}

List<MapEntry<String, double>> sortedDesc(Map<String, double> values) =>
    values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

/// Currencies present in the data, most-used first.
List<String> currenciesByUse(Iterable<Transaction> rows) {
  final counts = <String, int>{};
  for (final r in rows) {
    counts[r.currency] = (counts[r.currency] ?? 0) + 1;
  }
  final list = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return list;
}

/// The currency to display: the user's pick if still present, else the preferred default if present, else the most used.
String resolveCurrency(Iterable<Transaction> rows, {required String preferred, String? selected}) {
  final available = currenciesByUse(rows);
  if (selected != null && available.contains(selected)) return selected;
  if (available.contains(preferred)) return preferred;
  return available.isNotEmpty ? available.first : preferred;
}

/// Spent against a budget in [month]; budgets are per currency, optionally per category.
double budgetSpent(Budget budget, Iterable<Transaction> rows, DateTime month) {
  var minor = 0;
  for (final r in rows) {
    if (r.type != 'expense' || r.currency != budget.currency || !sameMonth(r.txnDate, month)) continue;
    if (budget.categoryId != null && r.categoryId != budget.categoryId) continue;
    minor += r.amountMinor;
  }
  return minor / currencyMinorUnitFactor(budget.currency);
}

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;
