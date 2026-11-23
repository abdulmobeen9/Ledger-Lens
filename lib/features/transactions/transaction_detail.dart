import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart';
import 'transaction_widgets.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transactionByIdProvider(id));
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <LocalCategory>[];
    final hide = ref.watch(settingsProvider.select((s) => s.hideBalances));
    final row = async.valueOrNull;
    LocalCategory? category;
    if (row?.categoryId != null) {
      for (final c in categories) {
        if (c.id == row!.categoryId) category = c;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (row != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  context.push('/transactions/$id/edit');
                } else if (value == 'duplicate') {
                  context.push('/add?type=${row.type}&from=$id');
                } else if (value == 'delete') {
                  final ok = await confirmDialog(
                    context,
                    title: 'Delete transaction?',
                    message: 'This removes it from this device and from your other devices once synced.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (!ok) return;
                  await ref.read(transactionRepositoryProvider).delete(id);
                  if (context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero)),
                PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Duplicate'), contentPadding: EdgeInsets.zero)),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.expense), title: Text('Delete'), contentPadding: EdgeInsets.zero)),
              ],
            ),
        ],
      ),
      body: async.isLoading && row == null
          ? const Center(child: CircularProgressIndicator())
          : row == null
              ? const EmptyView(icon: Icons.search_off_rounded, title: 'Transaction not found', message: 'It may have been deleted on another device.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    _Hero(row: row, category: category, hide: hide),
                    const SizedBox(height: 16),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      child: Column(children: [
                        _DetailRow(Icons.category_rounded, 'Category', category?.name ?? 'Uncategorized'),
                        _DetailRow(Icons.account_balance_wallet_outlined, 'Payment method', methodLabel(row.transferMethod)),
                        _DetailRow(Icons.tag_rounded, 'Reference number', row.referenceNo ?? '—'),
                        _DetailRow(Icons.call_received_rounded, 'Receiving number', row.receivingNumber ?? '—'),
                        _DetailRow(Icons.notes_rounded, 'Notes', row.notes ?? '—'),
                        _DetailRow(
                          row.extractionSource == 'manual' ? Icons.edit_note_rounded : Icons.auto_awesome_rounded,
                          'Source',
                          row.extractionSource == 'manual' ? 'Entered manually' : 'Scanned receipt',
                          last: true,
                        ),
                      ]),
                    ),
                    if (row.imageUrl != null) ...[
                      const SizedBox(height: 20),
                      const SectionHeader('Receipt'),
                      const SizedBox(height: 10),
                      _ReceiptImage(path: row.imageUrl!),
                    ],
                  ],
                ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.row, required this.category, required this.hide});
  final Transaction row;
  final LocalCategory? category;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final income = row.type == 'income';
    final accent = income ? AppColors.income : AppColors.expense;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(children: [
        CategoryAvatar(icon: category?.icon ?? (income ? 'trending_up' : 'category'), colorHex: category?.color ?? (income ? '#10B981' : '#64748B'), size: 62),
        const SizedBox(height: 16),
        Text(
          Money.format(income ? row.preciseAmount : -row.preciseAmount, row.currency, signed: true, hide: hide),
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: accent),
        ),
        const SizedBox(height: 6),
        Text(
          (row.counterpartyName?.isNotEmpty ?? false) ? row.counterpartyName! : (income ? 'Income' : 'Expense'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(Dates.dayLong(row.txnDate), style: TextStyle(color: context.mutedText)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(income ? 'INCOME' : 'EXPENSE', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8)),
        ),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value, {this.last = false});
  final IconData icon;
  final String label, value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: context.borderColor))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: context.mutedText),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.mutedText, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ]),
          ),
        ]),
      );
}

class _ReceiptImage extends ConsumerWidget {
  const _ReceiptImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String>(
        future: ref.read(transactionRepositoryProvider).signedReceiptUrl(path),
        builder: (context, snap) {
          if (snap.hasError) return const Text('Receipt preview unavailable (you may be offline).');
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.network(
              snap.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('Receipt preview unavailable'),
            ),
          );
        },
      );
}
