import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/category_style.dart';
import '../../core/charts.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import '../../domain/analytics.dart';
import '../transactions/transaction_widgets.dart';
import 'app_drawer.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime month = monthStart(DateTime.now());
  String? currency;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final settings = ref.watch(settingsProvider);
    final hide = settings.hideBalances;
    final name = (user?.email ?? '').split('@').first;
    final txAsync = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[];
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <SavingsGoal>[];
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leadingWidth: 68,
        leading: const MenuButton(),
        titleSpacing: 6,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${Dates.greeting()}${name.isEmpty ? '' : ','}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.mutedText)),
            Text(name.isEmpty ? 'LedgerLens' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            tooltip: hide ? 'Show amounts' : 'Hide amounts',
            onPressed: () => ref.read(settingsProvider.notifier).setHideBalances(!hide),
            icon: Icon(hide ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          ),
          IconButton(
            tooltip: 'Sync',
            onPressed: () async {
              await ref.read(transactionRepositoryProvider).syncPending();
              if (context.mounted) showSnack(context, 'Sync finished');
            },
            icon: const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAdd(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyView(icon: Icons.error_outline_rounded, title: 'Could not load your ledger', message: '$e'),
        data: (rows) {
          final cur = resolveCurrency(rows, preferred: settings.defaultCurrency, selected: currency);
          final currencies = currenciesByUse(rows);
          final monthRows = inMonth(rows, month, cur);
          final totals = totalsOf(monthRows, cur);
          final previous = totalsOf(inMonth(rows, DateTime(month.year, month.month - 1), cur), cur);
          final trend = monthlyTrend(rows, month, 6, cur);
          final byCategory = sortedDesc(expenseByCategory(monthRows, cur));
          final allMonthRows = rows.where((r) => sameMonth(r.txnDate, month)).toList();
          final canNext = month.isBefore(monthStart(DateTime.now()));

          return RefreshIndicator(
            onRefresh: () => ref.read(transactionRepositoryProvider).syncPending(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 110),
              children: [
                _HeroCard(
                  month: month,
                  currency: cur,
                  currencies: currencies.isEmpty ? [cur] : currencies,
                  totals: totals,
                  hide: hide,
                  canNext: canNext,
                  onPrev: () => setState(() => month = DateTime(month.year, month.month - 1)),
                  onNext: () => setState(() => month = DateTime(month.year, month.month + 1)),
                  onCurrency: (c) => setState(() => currency = c),
                ),
                const SizedBox(height: 18),
                const _QuickActions(),
                const SizedBox(height: 22),
                if (allMonthRows.length > monthRows.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _Notice(text: 'Some transactions this month use other currencies. Use the currency selector above to switch.'),
                  ),
                _BudgetSnapshot(budgets: budgets, rows: rows, month: month, currency: cur, categories: byId, hide: hide),
                const SizedBox(height: 22),
                const SectionHeader('Cash flow • last 6 months'),
                const SizedBox(height: 10),
                SoftCard(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  child: Column(children: [
                    CashFlowChart(points: trend),
                    const SizedBox(height: 10),
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _Legend(color: AppColors.income, label: 'Income'),
                      SizedBox(width: 18),
                      _Legend(color: AppColors.expense, label: 'Expenses'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 22),
                if (byCategory.isNotEmpty) ...[
                  SectionHeader('Spending by category', actionLabel: 'Reports', onAction: () => context.push('/reports')),
                  const SizedBox(height: 10),
                  _CategoryBreakdown(entries: byCategory, categories: byId, currency: cur, total: totals.expense, hide: hide),
                  const SizedBox(height: 22),
                ],
                if (monthRows.isNotEmpty) ...[
                  const SectionHeader('Insights'),
                  const SizedBox(height: 10),
                  _Insights(month: month, currency: cur, totals: totals, previous: previous, byCategory: byCategory, categories: byId, hide: hide),
                  const SizedBox(height: 22),
                ],
                if (goals.isNotEmpty) ...[
                  SectionHeader('Savings goals', actionLabel: 'Manage', onAction: () => context.push('/goals')),
                  const SizedBox(height: 10),
                  _GoalsSnapshot(goals: goals.take(2).toList(), hide: hide),
                  const SizedBox(height: 22),
                ],
                SectionHeader('Recent activity', actionLabel: 'See all', onAction: () => context.push('/transactions')),
                const SizedBox(height: 6),
                if (monthRows.isEmpty)
                  SoftCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        Icon(Icons.receipt_long_rounded, size: 40, color: context.mutedText),
                        const SizedBox(height: 10),
                        const Text('Nothing recorded this month', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Add an income or expense to see your picture here.', style: TextStyle(color: context.mutedText), textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        OutlinedButton(onPressed: () => context.push('/add?type=expense'), child: const Text('Add transaction')),
                      ]),
                    ),
                  )
                else
                  SoftCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(children: [
                      for (final r in monthRows.take(8))
                        TransactionTile(
                          txn: r,
                          category: byId[r.categoryId],
                          hide: hide,
                          onTap: () => context.push('/transactions/${r.id}'),
                        ),
                    ]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAdd(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetAction(icon: Icons.south_west_rounded, color: AppColors.income, label: 'Add income', onTap: () { Navigator.pop(sheet); context.push('/add?type=income'); }),
            _SheetAction(icon: Icons.north_east_rounded, color: AppColors.expense, label: 'Add expense', onTap: () { Navigator.pop(sheet); context.push('/add?type=expense'); }),
            _SheetAction(icon: Icons.document_scanner_rounded, color: const Color(0xFF0EA5E9), label: 'Scan receipt or transfer', onTap: () { Navigator.pop(sheet); context.push('/scan'); }),
          ]),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: IconBadge(icon: icon, color: color),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.month,
    required this.currency,
    required this.currencies,
    required this.totals,
    required this.hide,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onCurrency,
  });

  final DateTime month;
  final String currency;
  final List<String> currencies;
  final Totals totals;
  final bool hide, canNext;
  final VoidCallback onPrev, onNext;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    final rate = totals.savingsRate;
    return SoftCard(
      gradient: AppColors.heroGradient,
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
            Text(Dates.month(month), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            IconButton(onPressed: canNext ? onNext : null, icon: Icon(Icons.chevron_right_rounded, color: canNext ? Colors.white : Colors.white30)),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: onCurrency,
              itemBuilder: (_) => [for (final c in currencies) PopupMenuItem(value: c, child: Text(c))],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(currency, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                ]),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              const Text('Net balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Money.format(totals.net, currency, hide: hide),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: _FlowChip(label: 'Income', value: Money.format(totals.income, currency, hide: hide), icon: Icons.south_west_rounded, color: const Color(0xFF6EE7B7))),
                const SizedBox(width: 10),
                Expanded(child: _FlowChip(label: 'Expenses', value: Money.format(totals.expense, currency, hide: hide), icon: Icons.north_east_rounded, color: const Color(0xFFFDA4AF))),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                const Text('Savings rate', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
                const Spacer(),
                Text(totals.income <= 0 ? '—' : Money.percent(rate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              ThinProgress(value: rate < 0 ? 0 : rate, color: Colors.white, trackColor: Colors.white24, height: 7),
            ]),
          ),
        ],
      ),
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({required this.label, required this.value, required this.icon, required this.color});
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            ]),
          ),
        ]),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label, Color color, String route) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push(route),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                IconBadge(icon: icon, color: color, size: 54),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          ),
        );
    return Row(children: [
      action(Icons.south_west_rounded, 'Income', AppColors.income, '/add?type=income'),
      action(Icons.north_east_rounded, 'Expense', AppColors.expense, '/add?type=expense'),
      action(Icons.document_scanner_rounded, 'Scan', const Color(0xFF0EA5E9), '/scan'),
      action(Icons.insights_rounded, 'Reports', AppColors.violet, '/reports'),
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.mutedText, fontWeight: FontWeight.w600)),
      ]);
}

class _BudgetSnapshot extends StatelessWidget {
  const _BudgetSnapshot({required this.budgets, required this.rows, required this.month, required this.currency, required this.categories, required this.hide});
  final List<Budget> budgets;
  final List<Transaction> rows;
  final DateTime month;
  final String currency;
  final Map<String, LocalCategory> categories;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final relevant = budgets.where((b) => b.currency == currency).toList();
    if (relevant.isEmpty) {
      return SoftCard(
        onTap: () => context.push('/budgets'),
        child: Row(children: [
          const IconBadge(icon: Icons.donut_large_rounded, color: AppColors.warning),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Set a monthly budget', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Get a heads-up before you overspend.', style: TextStyle(fontSize: 12.5)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.mutedText),
        ]),
      );
    }
    final items = [
      for (final b in relevant) (b: b, spent: budgetSpent(b, rows, month)),
    ]..sort((a, b) {
        final ra = a.spent / (a.b.amountMinor / currencyMinorUnitFactor(currency));
        final rb = b.spent / (b.b.amountMinor / currencyMinorUnitFactor(currency));
        return rb.compareTo(ra);
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Budgets', actionLabel: 'Manage', onAction: () => context.push('/budgets')),
      const SizedBox(height: 10),
      SoftCard(
        child: Column(children: [
          for (var i = 0; i < items.length && i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _BudgetRow(budget: items[i].b, spent: items[i].spent, categories: categories, hide: hide),
          ],
        ]),
      ),
    ]);
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.budget, required this.spent, required this.categories, required this.hide});
  final Budget budget;
  final double spent;
  final Map<String, LocalCategory> categories;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final limit = budget.amountMinor / currencyMinorUnitFactor(budget.currency);
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    final color = ratio >= 1 ? AppColors.expense : (ratio >= 0.8 ? AppColors.warning : AppColors.income);
    final cat = budget.categoryId == null ? null : categories[budget.categoryId];
    return Column(children: [
      Row(children: [
        CategoryAvatar(icon: cat?.icon ?? 'savings', colorHex: cat?.color ?? '#4F46E5', size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text(budget.categoryId == null ? 'Overall budget' : (cat?.name ?? 'Category'), style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${Money.format(spent, budget.currency, hide: hide)} / ${Money.format(limit, budget.currency, hide: hide)}', style: TextStyle(fontSize: 12.5, color: context.mutedText, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      ThinProgress(value: ratio, color: color),
    ]);
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries, required this.categories, required this.currency, required this.total, required this.hide});
  final List<MapEntry<String, double>> entries;
  final Map<String, LocalCategory> categories;
  final String currency;
  final double total;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final top = entries.take(5).toList();
    final restValue = entries.skip(5).fold<double>(0, (s, e) => s + e.value);
    final slices = <DonutSlice>[
      for (var i = 0; i < top.length; i++)
        DonutSlice(
          top[i].key == kUncategorized ? 'Uncategorized' : (categories[top[i].key]?.name ?? 'Category'),
          top[i].value,
          top[i].key == kUncategorized ? AppColors.slate : kChartPalette[i % kChartPalette.length],
        ),
      if (restValue > 0) DonutSlice('Others', restValue, const Color(0xFF94A3B8)),
    ];
    return SoftCard(
      child: Column(children: [
        CategoryDonut(slices: slices, centerTop: 'Spent', centerBottom: Money.format(total, currency, hide: hide)),
        const SizedBox(height: 16),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(total <= 0 ? '' : Money.percent(s.value / total), style: TextStyle(color: context.mutedText, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(width: 12),
              Text(Money.format(s.value, currency, hide: hide), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.month, required this.currency, required this.totals, required this.previous, required this.byCategory, required this.categories, required this.hide});
  final DateTime month;
  final String currency;
  final Totals totals, previous;
  final List<MapEntry<String, double>> byCategory;
  final Map<String, LocalCategory> categories;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = sameMonth(month, now) ? now.day : daysInMonth(month);
    final dailyAverage = days <= 0 ? 0.0 : totals.expense / days;
    final topKey = byCategory.isEmpty ? null : byCategory.first.key;
    final topName = topKey == null ? '—' : (topKey == kUncategorized ? 'Uncategorized' : (categories[topKey]?.name ?? 'Category'));
    String change = '—';
    var up = false;
    if (previous.expense > 0) {
      final delta = (totals.expense - previous.expense) / previous.expense;
      up = delta > 0;
      change = '${delta >= 0 ? '+' : '−'}${(delta.abs() * 100).round()}%';
    }
    Widget tile(IconData icon, Color color, String label, String value) => Expanded(
          child: SoftCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(icon: icon, color: color, size: 36),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(fontSize: 11.5, color: context.mutedText, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
          ),
        );
    return Row(children: [
      tile(Icons.today_rounded, AppColors.brand, 'Daily average', Money.format(dailyAverage, currency, hide: hide)),
      const SizedBox(width: 10),
      tile(Icons.star_rounded, AppColors.warning, 'Top category', topName),
      const SizedBox(width: 10),
      tile(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, up ? AppColors.expense : AppColors.income, 'Spend vs last month', change),
    ]);
  }
}

class _GoalsSnapshot extends StatelessWidget {
  const _GoalsSnapshot({required this.goals, required this.hide});
  final List<SavingsGoal> goals;
  final bool hide;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: () => context.push('/goals'),
        child: Column(children: [
          for (var i = 0; i < goals.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _GoalRow(goal: goals[i], hide: hide),
          ],
        ]),
      );
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.hide});
  final SavingsGoal goal;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final ratio = goal.targetMinor <= 0 ? 0.0 : goal.savedMinor / goal.targetMinor;
    final color = hexColor('#14B8A6');
    return Column(children: [
      Row(children: [
        IconBadge(icon: Icons.savings_rounded, color: color, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(Money.percent(ratio), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ]),
      const SizedBox(height: 10),
      ThinProgress(value: ratio, color: color),
    ]);
  }
}
