import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import '../../domain/analytics.dart';
import '../transactions/transaction_widgets.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final rows = ref.watch(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[];
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final byId = {for (final c in categories) c.id: c};
    final month = monthStart(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New budget', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: budgets.isEmpty
          ? EmptyView(
              icon: Icons.donut_large_rounded,
              title: 'No budgets yet',
              message: 'Set a monthly limit overall or per category and track it as you spend.',
              actionLabel: 'Create a budget',
              onAction: () => _edit(context, ref, null),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
              children: [
                Text('Resets every month • ${Dates.month(month)}', style: TextStyle(color: context.mutedText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final b in budgets) ...[
                  _BudgetCard(
                    budget: b,
                    spent: budgetSpent(b, rows, month),
                    category: b.categoryId == null ? null : byId[b.categoryId],
                    hide: hide,
                    onTap: () => _edit(context, ref, b),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Budget? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BudgetSheet(existing: existing),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.spent, required this.category, required this.hide, required this.onTap});
  final Budget budget;
  final double spent;
  final LocalCategory? category;
  final bool hide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final limit = minorUnitsToAmount(budget.amountMinor, budget.currency);
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    final color = ratio >= 1 ? AppColors.expense : (ratio >= 0.8 ? AppColors.warning : AppColors.income);
    final remaining = limit - spent;
    final status = ratio >= 1
        ? 'Over by ${Money.format(-remaining, budget.currency, hide: hide)}'
        : '${Money.format(remaining, budget.currency, hide: hide)} left';
    return SoftCard(
      onTap: onTap,
      child: Column(children: [
        Row(children: [
          CategoryAvatar(icon: category?.icon ?? 'savings', colorHex: category?.color ?? '#4F46E5'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(budget.categoryId == null ? 'Overall budget' : (category?.name ?? 'Category'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
          Text(Money.percent(ratio), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
        ]),
        const SizedBox(height: 14),
        ThinProgress(value: ratio, color: color, height: 10),
        const SizedBox(height: 10),
        Row(children: [
          Text(Money.format(spent, budget.currency, hide: hide), style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('of ${Money.format(limit, budget.currency, hide: hide)}', style: TextStyle(color: context.mutedText, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({this.existing});
  final Budget? existing;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final amount = TextEditingController();
  String? categoryId;
  late String currency;
  String? error;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    currency = b?.currency ?? ref.read(settingsProvider).defaultCurrency;
    categoryId = b?.categoryId;
    if (b != null) amount.text = minorUnitsToAmount(b.amountMinor, b.currency).toStringAsFixed(Money.digits(b.currency));
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseAmount(amount.text);
    if (value == null) {
      setState(() => error = 'Enter an amount greater than zero');
      return;
    }
    final uid = ref.read(supabaseProvider).auth.currentUser?.id;
    if (uid == null) return;
    final budgets = ref.read(budgetsProvider).valueOrNull ?? const <Budget>[];
    final clash = budgets.any((b) => b.id != widget.existing?.id && b.categoryId == categoryId && b.currency == currency);
    if (clash) {
      setState(() => error = 'You already have a budget for this category in $currency');
      return;
    }
    await ref.read(databaseProvider).budgetDao.upsert(BudgetsCompanion.insert(
          id: widget.existing?.id ?? const Uuid().v4(),
          userId: uid,
          categoryId: Value(categoryId),
          amountMinor: amountToMinorUnits(value, currency),
          currency: Value(currency),
          createdAt: widget.existing?.createdAt ?? DateTime.now(),
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Delete budget?', message: 'Your transactions are not affected.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    await ref.read(databaseProvider).budgetDao.deleteById(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[]).where((c) => c.type != 'income').toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.existing == null ? 'New monthly budget' : 'Edit budget', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const FieldLabel('APPLIES TO'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('Overall'), selected: categoryId == null, showCheckmark: false, onSelected: (_) => setState(() => categoryId = null)),
            for (final c in categories)
              ChoiceChip(label: Text(c.name), selected: categoryId == c.id, showCheckmark: false, onSelected: (_) => setState(() => categoryId = c.id)),
          ]),
          const FieldLabel('MONTHLY LIMIT'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount', errorText: error),
              ),
            ),
            const SizedBox(width: 10),
            CurrencyButton(value: currency, onChanged: (c) => setState(() => currency = c)),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save budget')),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _delete, child: const Text('Delete budget', style: TextStyle(color: AppColors.expense))),
          ],
        ]),
      ),
    );
  }
}
