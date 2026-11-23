import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int months = 6;
  String? currency;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(transactionsProvider);
    final settings = ref.watch(settingsProvider);
    final hide = settings.hideBalances;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[];
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & analytics')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyView(icon: Icons.error_outline_rounded, title: 'Could not load data', message: '$e'),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyView(
              icon: Icons.insights_rounded,
              title: 'No data to analyse yet',
              message: 'Record a few transactions and your reports will appear here.',
            );
          }
          final cur = resolveCurrency(rows, preferred: settings.defaultCurrency, selected: currency);
          final currencies = currenciesByUse(rows);
          final now = monthStart(DateTime.now());
          final from = DateTime(now.year, now.month - (months - 1));
          final periodRows = rows.where((r) => r.currency == cur && !r.txnDate.isBefore(from)).toList();
          final totals = totalsOf(periodRows, cur);
          final trend = monthlyTrend(rows, now, months, cur);
          final byCategory = sortedDesc(expenseByCategory(periodRows, cur));
          final topPeople = sortedDesc(sumByLabel(periodRows, cur, 'expense', (r) => r.counterpartyName)).take(5).toList();
          final byMethod = sortedDesc(sumByLabel(periodRows, cur, 'expense', (r) => methodLabel(r.transferMethod)));
          final best = trend.isEmpty ? null : trend.reduce((a, b) => a.net >= b.net ? a : b);
          final avgExpense = months == 0 ? 0.0 : totals.expense / months;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(children: [
                for (final m in const [3, 6, 12])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${m}M'),
                      selected: months == m,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => months = m),
                    ),
                  ),
                const Spacer(),
                if (currencies.length > 1)
                  PopupMenuButton<String>(
                    onSelected: (c) => setState(() => currency = c),
                    itemBuilder: (_) => [for (final c in currencies) PopupMenuItem(value: c, child: Text(c))],
                    child: Chip(label: Text(cur), avatar: const Icon(Icons.currency_exchange_rounded, size: 18)),
                  )
                else
                  Chip(label: Text(cur)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _Stat(label: 'Income', value: Money.format(totals.income, cur, hide: hide), color: AppColors.income, icon: Icons.south_west_rounded),
                const SizedBox(width: 10),
                _Stat(label: 'Expenses', value: Money.format(totals.expense, cur, hide: hide), color: AppColors.expense, icon: Icons.north_east_rounded),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _Stat(label: 'Net saved', value: Money.format(totals.net, cur, hide: hide), color: AppColors.brand, icon: Icons.savings_rounded),
                const SizedBox(width: 10),
                _Stat(label: 'Avg. monthly spend', value: Money.format(avgExpense, cur, hide: hide), color: AppColors.warning, icon: Icons.calendar_view_month_rounded),
              ]),
              const SizedBox(height: 22),
              const SectionHeader('Income vs expenses'),
              const SizedBox(height: 10),
              SoftCard(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 14),
                child: Column(children: [
                  CashFlowChart(points: trend, height: 200),
                  if (best != null && (best.income > 0 || best.expense > 0)) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Best month: ${Dates.month(best.month)} (${Money.format(best.net, cur, signed: true, hide: hide)})',
                      style: TextStyle(color: context.mutedText, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ]),
              ),
              if (byCategory.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionHeader('Where your money goes'),
                const SizedBox(height: 10),
                SoftCard(
                  child: Column(children: [
                    for (var i = 0; i < byCategory.length && i < 8; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _BarRow(
                        label: byCategory[i].key == kUncategorized ? 'Uncategorized' : (byId[byCategory[i].key]?.name ?? 'Category'),
                        amount: Money.format(byCategory[i].value, cur, hide: hide),
                        ratio: totals.expense <= 0 ? 0 : byCategory[i].value / totals.expense,
                        color: byCategory[i].key == kUncategorized ? AppColors.slate : hexColor(byId[byCategory[i].key]?.color, fallback: kChartPalette[i % kChartPalette.length]),
                      ),
                    ],
                  ]),
                ),
              ],
              if (topPeople.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionHeader('Top payees'),
                const SizedBox(height: 10),
                SoftCard(
                  child: Column(children: [
                    for (var i = 0; i < topPeople.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _BarRow(
                        label: topPeople[i].key,
                        amount: Money.format(topPeople[i].value, cur, hide: hide),
                        ratio: totals.expense <= 0 ? 0 : topPeople[i].value / totals.expense,
                        color: kChartPalette[i % kChartPalette.length],
                      ),
                    ],
                  ]),
                ),
              ],
              if (byMethod.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionHeader('Payment methods'),
                const SizedBox(height: 10),
                SoftCard(
                  child: Column(children: [
                    for (var i = 0; i < byMethod.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _BarRow(
                        label: byMethod[i].key,
                        amount: Money.format(byMethod[i].value, cur, hide: hide),
                        ratio: totals.expense <= 0 ? 0 : byMethod[i].value / totals.expense,
                        color: kChartPalette[(i + 3) % kChartPalette.length],
                      ),
                    ],
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, required this.icon});
  final String label, value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconBadge(icon: icon, color: color, size: 36),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontSize: 12, color: context.mutedText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
        ),
      );
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.amount, required this.ratio, required this.color});
  final String label, amount;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text(Money.percent(ratio), textAlign: TextAlign.right, style: TextStyle(color: context.mutedText, fontSize: 12.5, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        ThinProgress(value: ratio, color: color, height: 7),
      ]);
}
