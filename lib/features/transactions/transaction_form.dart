import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/app_database.dart'; 
import '../../domain/duplicates.dart';
import 'transaction_widgets.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, required this.type, this.transactionId, this.duplicateFromId});
  final String type;
  final String? transactionId;
  final String? duplicateFromId;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final name = TextEditingController();
  final notes = TextEditingController();
  final reference = TextEditingController();
  final receiving = TextEditingController();
  DateTime date = DateTime.now();
  String type = 'expense';
  late String currency;
  String method = 'cash';
  String? categoryId, imageUrl;
  bool saving = false, loading = false;

  @override
  void initState() {
    super.initState();
    type = widget.type == 'income' ? 'income' : 'expense';
    currency = ref.read(settingsProvider).defaultCurrency;
    final sourceId = widget.transactionId ?? widget.duplicateFromId;
    if (sourceId != null) _load(sourceId);
  }

  Future<void> _load(String id) async {
    setState(() => loading = true);
    try {
      final row = await ref.read(databaseProvider).transactionDao.byId(id);
      if (row != null && mounted) {
        final isEdit = widget.transactionId != null;
        amount.text = row.preciseAmount.toStringAsFixed(2);
        name.text = row.counterpartyName ?? '';
        notes.text = row.notes ?? '';
        type = row.type;
        currency = row.currency;
        method = row.transferMethod ?? 'other';
        categoryId = row.categoryId;
        if (isEdit) {
          // A duplicate is a new entry: fresh date, no copied reference numbers or receipt image.
          reference.text = row.referenceNo ?? '';
          receiving.text = row.receivingNumber ?? '';
          date = row.txnDate;
          imageUrl = row.imageUrl;
        }
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    amount.dispose();
    name.dispose();
    notes.dispose();
    reference.dispose();
    receiving.dispose();
    super.dispose();
  }

  String? _blankToNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    if (widget.transactionId == null) {
      final uid = ref.read(supabaseProvider).auth.currentUser?.id;
      if (uid != null) {
        final saved = await ref.read(databaseProvider).transactionDao.getAll(uid);
        final match = findDuplicate(
          saved,
          reference: reference.text,
          amount: parseAmount(amount.text),
          currency: currency,
          date: date,
          name: name.text,
          receiving: receiving.text,
        );
        if (match != null && mounted) {
          final choice = await showDuplicateDialog(context, match);
          if (choice == 'view') {
            if (mounted) context.push('/transactions/${match.transaction.id}');
            return;
          }
          if (choice != 'save') return;
        }
      }
    }
    setState(() => saving = true);
    try {
      await ref.read(transactionRepositoryProvider).save(
            id: widget.transactionId,
            type: type,
            amount: parseAmount(amount.text)!,
            currency: currency,
            date: date,
            name: _blankToNull(name),
            method: method,
            reference: _blankToNull(reference),
            receiving: _blankToNull(receiving),
            notes: _blankToNull(notes),
            categoryId: categoryId,
            imageUrl: imageUrl,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accent = type == 'income' ? AppColors.income : AppColors.expense;
    final title = widget.transactionId != null
        ? 'Edit transaction'
        : (widget.duplicateFromId != null ? 'Duplicate transaction' : 'New transaction');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TypeToggle(
                      value: type,
                      onChanged: (v) => setState(() {
                        type = v;
                        categoryId = null;
                      }),
                    ),
                    const SizedBox(height: 18),
                    SoftCard(
                      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: accent),
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                hintText: '0.00',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              validator: (v) => parseAmount(v ?? '') == null ? 'Enter an amount greater than zero' : null,
                            ),
                          ),
                          CurrencyButton(value: currency, onChanged: (c) => setState(() => currency = c)),
                        ],
                      ),
                    ),
                    const FieldLabel('CATEGORY'),
                    CategoryPicker(
                      categories: categories,
                      type: type,
                      selectedId: categoryId,
                      onChanged: (id) => setState(() => categoryId = id),
                    ),
                    const FieldLabel('DATE'),
                    DateField(date: date, onChanged: (d) => setState(() => date = d)),
                    const FieldLabel('PAYMENT METHOD'),
                    MethodPicker(value: method, onChanged: (m) => setState(() => method = m)),
                    const FieldLabel('DETAILS'),
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Person / business (optional)', prefixIcon: Icon(Icons.person_outline_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reference,
                      decoration: const InputDecoration(labelText: 'Reference number (optional)', prefixIcon: Icon(Icons.tag_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: receiving,
                      decoration: const InputDecoration(labelText: 'Receiving number (optional)', prefixIcon: Icon(Icons.call_received_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notes,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes_rounded)),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      style: FilledButton.styleFrom(backgroundColor: accent),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(saving ? 'Saving…' : 'Save transaction'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
