import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/category_style.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import '../transactions/transaction_widgets.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyView(icon: Icons.error_outline_rounded, title: 'Could not load categories', message: '$e'),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyView(
              icon: Icons.category_rounded,
              title: 'No categories yet',
              message: 'Add one to organise your ledger. Default categories appear after your first online sign-in.',
              actionLabel: 'Add category',
              onAction: () => _edit(context, null),
            );
          }
          Widget group(String title, List<LocalCategory> items) => items.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 8), child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 1, color: context.mutedText))),
                  SoftCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(children: [
                      for (final c in items)
                        ListTile(
                          onTap: () => _edit(context, c),
                          leading: CategoryAvatar(icon: c.icon, colorHex: c.color, size: 42),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete "${c.name}"?',
                                message: 'Transactions keep their data but become uncategorized. Budgets for this category are removed.',
                                confirmLabel: 'Delete',
                                destructive: true,
                              );
                              if (ok) await ref.read(transactionRepositoryProvider).deleteCategory(c.id);
                            },
                          ),
                        ),
                    ]),
                  ),
                ]);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            children: [
              group('EXPENSE', rows.where((c) => c.type == 'expense').toList()),
              group('INCOME', rows.where((c) => c.type == 'income').toList()),
              group('BOTH', rows.where((c) => c.type == 'both').toList()),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, LocalCategory? category) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CategorySheet(existing: category),
      );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing});
  final LocalCategory? existing;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  final name = TextEditingController();
  String type = 'expense', icon = 'category', color = kCategoryColors.first;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      name.text = c.name;
      type = c.type;
      icon = c.icon;
      color = c.color;
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter a name');
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(transactionRepositoryProvider).saveCategory(id: widget.existing?.id, name: name.text, type: type, icon: icon, color: color);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { error = '$e'.replaceFirst('Exception: ', ''); busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              CategoryAvatar(icon: icon, colorHex: color, size: 52),
              const SizedBox(width: 14),
              Text(widget.existing == null ? 'New category' : 'Edit category', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Name', errorText: error)),
            const FieldLabel('USED FOR'),
            Wrap(spacing: 8, children: [
              for (final t in const [('expense', 'Expenses'), ('income', 'Income'), ('both', 'Both')])
                ChoiceChip(label: Text(t.$2), selected: type == t.$1, showCheckmark: false, onSelected: (_) => setState(() => type = t.$1)),
            ]),
            const FieldLabel('ICON'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in kCategoryIcons.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => icon = entry.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: icon == entry.key ? hexColor(color).withValues(alpha: 0.18) : context.fieldFill,
                      borderRadius: BorderRadius.circular(12),
                      border: icon == entry.key ? Border.all(color: hexColor(color), width: 1.6) : null,
                    ),
                    child: Icon(entry.value, color: icon == entry.key ? hexColor(color) : context.mutedText),
                  ),
                ),
            ]),
            const FieldLabel('COLOUR'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final hex in kCategoryColors)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => color = hex),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: hexColor(hex), shape: BoxShape.circle),
                    child: color == hex ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 22),
            FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save category')),
          ]),
        ),
      );
}
