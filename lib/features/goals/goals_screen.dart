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
import '../transactions/transaction_widgets.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <SavingsGoal>[];
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: goals.isEmpty
          ? EmptyView(
              icon: Icons.savings_rounded,
              title: 'No savings goals yet',
              message: 'Save for a trip, an emergency fund or a new phone and watch your progress grow.',
              actionLabel: 'Create a goal',
              onAction: () => _edit(context, null),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
              children: [
                for (final g in goals) ...[
                  _GoalCard(goal: g, hide: hide, onEdit: () => _edit(context, g), onAddFunds: () => _addFunds(context, ref, g)),
                  const SizedBox(height: 12),
                ],
                Text('Goal progress is tracked manually and stored on this device.', textAlign: TextAlign.center, style: TextStyle(color: context.mutedText, fontSize: 12)),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, SavingsGoal? goal) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _GoalSheet(existing: goal),
      );

  Future<void> _addFunds(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to ${goal.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount (${goal.currency})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, parseAmount(controller.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final next = goal.savedMinor + amountToMinorUnits(result, goal.currency);
    await ref.read(databaseProvider).goalDao.setSaved(goal.id, next);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.hide, required this.onEdit, required this.onAddFunds});
  final SavingsGoal goal;
  final bool hide;
  final VoidCallback onEdit, onAddFunds;

  @override
  Widget build(BuildContext context) {
    final ratio = goal.targetMinor <= 0 ? 0.0 : (goal.savedMinor / goal.targetMinor);
    final done = ratio >= 1;
    final color = done ? AppColors.income : const Color(0xFF14B8A6);
    final saved = minorUnitsToAmount(goal.savedMinor, goal.currency);
    final target = minorUnitsToAmount(goal.targetMinor, goal.currency);
    final left = (target - saved).clamp(0.0, double.infinity).toDouble();
    String? deadline;
    if (goal.targetDate != null) {
      final days = goal.targetDate!.difference(DateTime.now()).inDays;
      deadline = done ? null : (days < 0 ? 'Past target date' : '$days days left • ${Dates.day(goal.targetDate!)}');
    }
    return SoftCard(
      onTap: onEdit,
      child: Row(children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 76,
              height: 76,
              child: CircularProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), strokeWidth: 8, strokeCap: StrokeCap.round, color: color, backgroundColor: color.withValues(alpha: 0.15)),
            ),
            Text(done ? '✓' : Money.percent(ratio), style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: done ? 22 : 15)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${Money.format(saved, goal.currency, hide: hide)} of ${Money.format(target, goal.currency, hide: hide)}', style: TextStyle(color: context.mutedText, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (!done) Text('${Money.format(left, goal.currency, hide: hide)} to go', style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
            if (deadline != null) Text(deadline, style: TextStyle(color: context.mutedText, fontSize: 12)),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: onAddFunds,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add funds'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({this.existing});
  final SavingsGoal? existing;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  final name = TextEditingController();
  final target = TextEditingController();
  late String currency;
  DateTime? targetDate;
  String? error;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    currency = g?.currency ?? ref.read(settingsProvider).defaultCurrency;
    if (g != null) {
      name.text = g.name;
      target.text = minorUnitsToAmount(g.targetMinor, g.currency).toStringAsFixed(Money.digits(g.currency));
      targetDate = g.targetDate;
    }
  }

  @override
  void dispose() {
    name.dispose();
    target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseAmount(target.text);
    if (name.text.trim().isEmpty || value == null) {
      setState(() => error = 'Enter a name and a target amount greater than zero');
      return;
    }
    final uid = ref.read(supabaseProvider).auth.currentUser?.id;
    if (uid == null) return;
    await ref.read(databaseProvider).goalDao.upsert(SavingsGoalsCompanion.insert(
          id: widget.existing?.id ?? const Uuid().v4(),
          userId: uid,
          name: name.text.trim(),
          targetMinor: amountToMinorUnits(value, currency),
          savedMinor: Value(widget.existing?.savedMinor ?? 0),
          currency: Value(currency),
          targetDate: Value(targetDate),
          createdAt: widget.existing?.createdAt ?? DateTime.now(),
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Delete goal?', message: 'Your saved progress for this goal will be removed.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    await ref.read(databaseProvider).goalDao.deleteById(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.existing == null ? 'New savings goal' : 'Edit goal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Goal name', prefixIcon: Icon(Icons.flag_rounded))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Target amount', errorText: error),
                ),
              ),
              const SizedBox(width: 10),
              CurrencyButton(value: currency, onChanged: (c) => setState(() => currency = c)),
            ]),
            const FieldLabel('TARGET DATE (OPTIONAL)'),
            Row(children: [
              Expanded(
                child: DateField(date: targetDate ?? DateTime.now().add(const Duration(days: 90)), onChanged: (d) => setState(() => targetDate = d)),
              ),
              if (targetDate != null) IconButton(onPressed: () => setState(() => targetDate = null), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save goal')),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _delete, child: const Text('Delete goal', style: TextStyle(color: AppColors.expense))),
            ],
          ]),
        ),
      );
}
