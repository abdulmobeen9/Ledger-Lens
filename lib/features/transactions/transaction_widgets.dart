import 'package:flutter/material.dart';
import '../../core/category_style.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import '../../domain/duplicates.dart';

const List<({String value, String label, IconData icon})> kMethods = [
  (value: 'bank', label: 'Bank', icon: Icons.account_balance_rounded),
  (value: 'cash', label: 'Cash', icon: Icons.payments_rounded),
  (value: 'wallet', label: 'Wallet', icon: Icons.account_balance_wallet_rounded),
  (value: 'card', label: 'Card', icon: Icons.credit_card_rounded),
  (value: 'other', label: 'Other', icon: Icons.more_horiz_rounded),
];

String methodLabel(String? value) {
  for (final m in kMethods) {
    if (m.value == value) return m.label;
  }
  return 'Not specified';
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.txn,
    this.category,
    this.hide = false,
    this.onTap,
  });

  final Transaction txn;
  final LocalCategory? category;
  final bool hide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final income = txn.type == 'income';
    final accent = income ? AppColors.income : AppColors.expense;
    final title = (txn.counterpartyName?.isNotEmpty ?? false)
        ? txn.counterpartyName!
        : (category?.name ?? (income ? 'Income' : 'Expense'));
    final subtitle = '${category?.name ?? 'Uncategorized'} • ${Dates.day(txn.txnDate)}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            CategoryAvatar(
              icon: category?.icon ?? (income ? 'trending_up' : 'category'),
              colorHex: category?.color ?? (income ? '#10B981' : '#64748B'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.mutedText, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Money.format(income ? txn.preciseAmount : -txn.preciseAmount, txn.currency, signed: true, hide: hide),
                  style: TextStyle(fontWeight: FontWeight.w800, color: accent, fontSize: 14.5),
                ),
                if (txn.pendingSync)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_upload_outlined, size: 12, color: context.mutedText),
                      const SizedBox(width: 3),
                      Text('Pending', style: TextStyle(fontSize: 11, color: context.mutedText)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TypeToggle extends StatelessWidget {
  const TypeToggle({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String type, String label, IconData icon, Color color) {
      final selected = value == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.white : context.mutedText),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : context.mutedText)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.fieldFill, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        option('income', 'Income', Icons.south_west_rounded, AppColors.income),
        option('expense', 'Expense', Icons.north_east_rounded, AppColors.expense),
      ]),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.mutedText, letterSpacing: 0.3)),
      );
}

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({super.key, required this.categories, required this.type, required this.selectedId, required this.onChanged});
  final List<LocalCategory> categories;
  final String type;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = categories.where((c) => c.type == 'both' || c.type == type).toList();
    if (options.isEmpty) {
      return Text('No categories yet. Sign in online once to load defaults, or add one from Categories.',
          style: TextStyle(color: context.mutedText));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in options)
          ChoiceChip(
            avatar: Icon(categoryIcon(c.icon), size: 18, color: hexColor(c.color)),
            label: Text(c.name),
            selected: selectedId == c.id,
            showCheckmark: false,
            onSelected: (on) => onChanged(on ? c.id : null),
          ),
      ],
    );
  }
}

class MethodPicker extends StatelessWidget {
  const MethodPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in kMethods)
            ChoiceChip(
              avatar: Icon(m.icon, size: 18),
              label: Text(m.label),
              selected: value == m.value,
              showCheckmark: false,
              onSelected: (_) => onChanged(m.value),
            ),
        ],
      );
}

Future<String?> pickCurrency(BuildContext context, String current) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Currency', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              for (final c in kCurrencies)
                ListTile(
                  title: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: c == current ? const Icon(Icons.check_circle_rounded) : null,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      ),
    );

class CurrencyButton extends StatelessWidget {
  const CurrencyButton({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await pickCurrency(context, value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: context.colors.primary)),
            Icon(Icons.keyboard_arrow_down_rounded, color: context.colors.primary),
          ]),
        ),
      );
}

class DateField extends StatelessWidget {
  const DateField({super.key, required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            initialDate: date,
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(color: context.fieldFill, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.calendar_month_rounded, color: context.mutedText),
            const SizedBox(width: 12),
            Text(Dates.dayLong(date), style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined, size: 18, color: context.mutedText),
          ]),
        ),
      );
}

double? parseAmount(String text) {
  final cleaned = text.replaceAll(',', '').replaceAll(' ', '').trim();
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

String describeTransaction(Transaction t) {
  final who = (t.counterpartyName?.isNotEmpty ?? false) ? t.counterpartyName! : (t.type == 'income' ? 'Income' : 'Expense');
  return '$who • ${Money.format(t.preciseAmount, t.currency)} • ${Dates.day(t.txnDate)}';
}

/// Returns 'view', 'save' (save anyway) or null (cancel).
Future<String?> showDuplicateDialog(BuildContext context, DuplicateMatch match) => showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(match.exact ? 'This slip already exists' : 'Possible duplicate'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('It matches a saved transaction by ${match.reason}.'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ctx.fieldFill, borderRadius: BorderRadius.circular(14)),
            child: Text(describeTransaction(match.transaction), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save anyway')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(ctx, 'view'),
            child: const Text('View slip'),
          ),
        ],
      ),
    );

class DuplicateBanner extends StatelessWidget {
  const DuplicateBanner({super.key, required this.match, required this.onView});
  final DuplicateMatch match;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final color = match.exact ? AppColors.expense : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(match.exact ? Icons.copy_all_rounded : Icons.help_outline_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(match.exact ? 'This slip is already saved' : 'This may already be saved',
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Matched by ${match.reason}:\n${describeTransaction(match.transaction)}'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onView,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('View saved slip'),
        ),
      ]),
    );
  }
}
