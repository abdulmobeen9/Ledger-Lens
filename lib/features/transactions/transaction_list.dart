import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import '../../domain/analytics.dart';
import 'transaction_widgets.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _Row {
  const _Row.header(this.day, this.dayTotal) : txn = null;
  const _Row.item(this.txn) : day = null, dayTotal = null;
  final DateTime? day;
  final String? dayTotal;
  final Transaction? txn;
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final search = TextEditingController();
  String type = 'all';
  String? category;
  DateTimeRange? range;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool get _filtered => range != null || category != null || type != 'all' || search.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[];
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () => context.push('/add?type=expense'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, notes or reference',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(onPressed: () => setState(search.clear), icon: const Icon(Icons.close_rounded)),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final t in const [('all', 'All'), ('income', 'Income'), ('expense', 'Expenses')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.$2),
                      selected: type == t.$1,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => type = t.$1),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PopupMenuButton<String?>(
                    onSelected: (v) => setState(() => category = v == '' ? null : v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: '', child: Text('All categories')),
                      for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: Text(category == null ? 'Category' : (byId[category]?.name ?? 'Category')),
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(range == null ? 'Dates' : '${Dates.day(range!.start)} – ${Dates.day(range!.end)}'),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: range,
                    );
                    if (picked != null) setState(() => range = picked);
                  },
                ),
                if (_filtered)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Clear'),
                      onPressed: () => setState(() {
                        range = null;
                        category = null;
                        type = 'all';
                        search.clear();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: all.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyView(icon: Icons.error_outline_rounded, title: 'Could not load transactions', message: '$e'),
              data: (rows) {
                final filtered = _apply(rows);
                if (filtered.isEmpty) {
                  return EmptyView(
                    icon: rows.isEmpty ? Icons.receipt_long_rounded : Icons.search_off_rounded,
                    title: rows.isEmpty ? 'No transactions yet' : 'Nothing matches',
                    message: rows.isEmpty ? 'Add your first income or expense to get started.' : 'Try changing or clearing the filters.',
                    actionLabel: rows.isEmpty ? 'Add transaction' : null,
                    onAction: rows.isEmpty ? () => context.push('/add?type=expense') : null,
                  );
                }
                final items = _group(filtered, hide);
                final currencies = currenciesByUse(filtered);
                return Column(
                  children: [
                    if (currencies.length == 1) _SummaryStrip(rows: filtered, currency: currencies.first, hide: hide),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => ref.read(transactionRepositoryProvider).syncPending(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            if (item.txn == null) return _DayHeader(day: item.day!, total: item.dayTotal!);
                            final r = item.txn!;
                            return Dismissible(
                              key: ValueKey(r.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                decoration: BoxDecoration(color: AppColors.expense, borderRadius: BorderRadius.circular(16)),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 22),
                                child: const Icon(Icons.delete_rounded, color: Colors.white),
                              ),
                              confirmDismiss: (_) async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Delete transaction?',
                                  message: 'It will also be removed from your other devices once synced.',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                );
                                if (!ok) return false;
                                await ref.read(transactionRepositoryProvider).delete(r.id);
                                return true;
                              },
                              child: TransactionTile(
                                txn: r,
                                category: byId[r.categoryId],
                                hide: hide,
                                onTap: () => context.push('/transactions/${r.id}'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add?type=expense'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  List<Transaction> _apply(List<Transaction> rows) {
    final q = search.text.trim().toLowerCase();
    final start = range == null ? null : DateTime(range!.start.year, range!.start.month, range!.start.day);
    final end = range == null ? null : DateTime(range!.end.year, range!.end.month, range!.end.day, 23, 59, 59);
    return rows.where((r) {
      if (type != 'all' && r.type != type) return false;
      if (category != null && r.categoryId != category) return false;
      if (start != null && r.txnDate.isBefore(start)) return false;
      if (end != null && r.txnDate.isAfter(end)) return false;
      if (q.isEmpty) return true;
      return [r.counterpartyName, r.notes, r.referenceNo, r.receivingNumber]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  List<_Row> _group(List<Transaction> rows, bool hide) {
    final items = <_Row>[];
    var i = 0;
    while (i < rows.length) {
      final d = rows[i].txnDate;
      final dayRows = <Transaction>[];
      while (i < rows.length && sameDay(rows[i].txnDate, d)) {
        dayRows.add(rows[i]);
        i++;
      }
      final currencies = currenciesByUse(dayRows);
      final total = currencies.length == 1
          ? Money.format(totalsOf(dayRows.where((r) => r.currency == currencies.first), currencies.first).net, currencies.first, signed: true, hide: hide)
          : '';
      items.add(_Row.header(d, total));
      items.addAll(dayRows.map(_Row.item));
    }
    return items;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.total});
  final DateTime day;
  final String total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Row(children: [
          Expanded(child: Text(Dates.dayHeader(day), style: TextStyle(fontWeight: FontWeight.w800, color: context.mutedText, fontSize: 13))),
          Text(total, style: TextStyle(fontWeight: FontWeight.w700, color: context.mutedText, fontSize: 13)),
        ]),
      );
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.rows, required this.currency, required this.hide});
  final List<Transaction> rows;
  final String currency;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final totals = totalsOf(rows.where((r) => r.currency == currency), currency);
    Widget cell(String label, double value, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: context.mutedText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(Money.format(value, currency, hide: hide), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          cell('Income', totals.income, AppColors.income),
          cell('Expenses', totals.expense, AppColors.expense),
          cell('Net', totals.net, context.colors.primary),
        ]),
      ),
    );
  }
}
