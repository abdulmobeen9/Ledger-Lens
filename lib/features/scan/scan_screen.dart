import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local/ai_key_store.dart';
import '../../data/remote/gemini_service.dart';
import '../../data/remote/supabase_service.dart';
import '../../domain/duplicates.dart';
import '../../domain/receipt_parser.dart';
import '../transactions/transaction_widgets.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final picker = ImagePicker();
  final List<File> images = [];
  bool busy = false, hasKey = false, useAi = true;
  String? rawText, imagePath;
  ParsedReceipt? parsed;
  DuplicateMatch? duplicate;
  final amount = TextEditingController();
  final name = TextEditingController();
  final reference = TextEditingController();
  final receiving = TextEditingController();
  final notes = TextEditingController();
  String type = 'expense', method = 'bank';
  late String currency;
  String? categoryId;
  DateTime date = DateTime.now();
  double confidence = 0;

  @override
  void initState() {
    super.initState();
    currency = ref.read(settingsProvider).defaultCurrency;
    _loadKey();
  }

  @override
  void dispose() {
    amount.dispose();
    name.dispose();
    reference.dispose();
    receiving.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await AiKeyStore.key();
    if (mounted) setState(() => hasKey = key != null && key.isNotEmpty);
  }

  Future<void> choose(ImageSource source) async {
    try {
      final picked = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1800);
      if (picked != null) {
        setState(() {
          images.add(File(picked.path));
          rawText = null;
          parsed = null;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the image source: $e');
    }
  }

  Future<ParsedReceipt> _readWithAi(String apiKey) async {
    final service = GeminiService();
    var model = await AiKeyStore.model();
    model ??= await service.pickModel(apiKey);
    await AiKeyStore.saveModel(model);
    try {
      return await service.extract(apiKey: apiKey, model: model, images: images);
    } on GeminiException catch (e) {
      if (!e.isNotFound) rethrow;
      // The saved model was retired: discover a current one and retry once.
      model = await service.pickModel(apiKey);
      await AiKeyStore.saveModel(model);
      return service.extract(apiKey: apiKey, model: model, images: images);
    }
  }

  /// Checks the saved ledger for the same slip using the values currently in the form.
  Future<DuplicateMatch?> _checkDuplicate() async {
    final uid = ref.read(supabaseProvider).auth.currentUser?.id;
    if (uid == null) return null;
    final saved = await ref.read(databaseProvider).transactionDao.getAll(uid);
    return findDuplicate(
      saved,
      reference: reference.text,
      transferCode: parsed?.extraReference,
      amount: parseAmount(amount.text),
      currency: currency,
      date: date,
      name: name.text,
      receiving: receiving.text,
    );
  }

  Future<void> extract() async {
    if (images.isEmpty) return;
    setState(() => busy = true);
    try {
      // 1. Free offline reading on the device (always runs).
      var text = '';
      try {
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final parts = <String>[];
          for (final file in images) {
            parts.add((await recognizer.processImage(InputImage.fromFile(file))).text);
          }
          text = parts.where((t) => t.trim().isNotEmpty).join('\n');
        } finally {
          await recognizer.close();
        }
      } catch (_) {
        text = '';
      }
      var result = parseReceiptText(text);

      // 2. Optional AI reading with the user's own free Gemini key; the offline result fills any gaps.
      final apiKey = (hasKey && useAi) ? await AiKeyStore.key() : null;
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          result = mergeReceipts(await _readWithAi(apiKey), result);
        } catch (e) {
          if (mounted) showSnack(context, 'AI unavailable: $e Using the offline reader instead.');
        }
      }

      if (text.trim().isEmpty && result.readBy != 'ai') {
        throw Exception('No readable text found. Try a clearer, well-lit photo, or add a free Gemini key in Settings.');
      }
      rawText = text.trim().isEmpty ? null : text;
      parsed = result;
      amount.text = result.amount?.toString() ?? '';
      name.text = result.name ?? '';
      reference.text = result.reference ?? '';
      receiving.text = result.receiving ?? '';
      notes.text = buildReceiptNotes(result);
      type = result.type;
      method = result.method ?? 'bank';
      currency = result.currency ?? currency;
      confidence = result.confidence;
      if (result.date != null) date = result.date!;
      duplicate = await _checkDuplicate();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm() async {
    final value = parseAmount(amount.text);
    if (value == null) {
      showSnack(context, 'Enter or correct the amount first.');
      return;
    }
    // Re-check with the current (possibly edited) values before saving.
    final existing = await _checkDuplicate();
    if (existing != null && mounted) {
      final choice = await showDuplicateDialog(context, existing);
      if (choice == 'view') {
        if (mounted) context.push('/transactions/${existing.transaction.id}');
        return;
      }
      if (choice != 'save') return;
    }
    setState(() => busy = true);
    try {
      // Receipt image upload is optional (Supabase free storage); the transaction saves even if it fails.
      try {
        final uid = ref.read(supabaseProvider).auth.currentUser!.id;
        imagePath ??= await SupabaseService(ref.read(supabaseProvider)).uploadReceipt(uid, images.first.path);
      } catch (_) {
        if (mounted) showSnack(context, 'Saved without the receipt image (upload failed).');
      }
      String? nullIfBlank(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final id = await ref.read(transactionRepositoryProvider).save(
            type: type,
            amount: value,
            currency: currency,
            date: date,
            name: nullIfBlank(name),
            method: method,
            reference: nullIfBlank(reference),
            receiving: nullIfBlank(receiving),
            notes: nullIfBlank(notes),
            imageUrl: imagePath,
            categoryId: categoryId,
            rawText: rawText,
            confidence: confidence,
            source: 'ocr_llm', // legacy label required by the database constraint
          );
      if (!mounted) return;
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Transaction saved'),
          action: SnackBarAction(label: 'Edit', onPressed: () => router.push('/transactions/$id/edit')),
        ));
    } catch (e) {
      if (mounted) showSnack(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Color? _flag(bool missing) => missing ? AppColors.warning.withValues(alpha: 0.14) : null;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final result = parsed;
    final lowConfidence = confidence < 0.7;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (images.isEmpty) ...[
            SoftCard(
              gradient: AppColors.heroGradient,
              padding: const EdgeInsets.all(24),
              child: const Column(children: [
                Icon(Icons.document_scanner_rounded, size: 52, color: Colors.white),
                SizedBox(height: 14),
                Text('Scan a receipt or transfer', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text(
                  'The text is read on your device for free. Review and edit every detail before saving; nothing is saved until you confirm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: busy ? null : () => choose(ImageSource.camera), icon: const Icon(Icons.camera_alt_rounded), label: const Text('Take photo')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: busy ? null : () => choose(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose from gallery')),
          ] else ...[
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(images[i], width: 240, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(onPressed: busy ? null : () => choose(ImageSource.gallery), icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add another')),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : () => setState(() { images.clear(); parsed = null; duplicate = null; imagePath = null; }),
                child: const Text('Remove all'),
              ),
            ]),
            if (result == null) ...[
              _AiCard(
                hasKey: hasKey,
                useAi: useAi,
                onToggle: (v) => setState(() => useAi = v),
                onSetup: () async {
                  await context.push('/settings');
                  await _loadKey();
                },
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: busy ? null : extract,
                icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.auto_awesome_rounded),
                label: Text(busy ? 'Reading receipt…' : 'Read receipt'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (lowConfidence ? AppColors.warning : AppColors.income).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Icon(lowConfidence ? Icons.warning_amber_rounded : Icons.verified_rounded, color: lowConfidence ? AppColors.warning : AppColors.income),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${result.readBy == 'ai' ? 'Read by Gemini AI' : 'Read offline'} • ${(confidence * 100).round()}% sure.\nEvery field below is editable. Highlighted fields were not found.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
              if (duplicate != null) ...[
                const SizedBox(height: 10),
                DuplicateBanner(match: duplicate!, onView: () => context.push('/transactions/${duplicate!.transaction.id}')),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : () => setState(() { parsed = null; duplicate = null; }),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Read again'),
                ),
              ),
              const SizedBox(height: 8),
              TypeToggle(value: type, onChanged: (v) => setState(() { type = v; categoryId = null; })),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Amount', fillColor: _flag(result.amount == null || confidence < 0.65)),
                  ),
                ),
                const SizedBox(width: 10),
                CurrencyButton(value: currency, onChanged: (c) => setState(() => currency = c)),
              ]),
              if (result.alternates.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Other amounts on this receipt (tap to use instead):', style: TextStyle(fontSize: 12, color: context.mutedText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in result.alternates)
                    ActionChip(
                      avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text('${Money.format(a.amount, a.currency)}${a.label == null ? '' : ' • ${a.label}'}'),
                      onPressed: () => setState(() {
                        amount.text = a.amount.toString();
                        currency = a.currency;
                      }),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Person / business', fillColor: _flag(result.name == null))),
              const SizedBox(height: 12),
              TextField(controller: reference, decoration: InputDecoration(labelText: 'Reference number', fillColor: _flag(result.reference == null))),
              const SizedBox(height: 12),
              TextField(controller: receiving, decoration: InputDecoration(labelText: 'Receiving number / IBAN', fillColor: _flag(result.receiving == null))),
              const SizedBox(height: 12),
              TextField(controller: notes, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const FieldLabel('CATEGORY'),
              CategoryPicker(categories: categories, type: type, selectedId: categoryId, onChanged: (id) => setState(() => categoryId = id)),
              const FieldLabel('DATE'),
              DateField(date: date, onChanged: (d) => setState(() => date = d)),
              const FieldLabel('PAYMENT METHOD'),
              MethodPicker(value: method, onChanged: (m) => setState(() => method = m)),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: busy ? null : confirm, icon: const Icon(Icons.check_rounded), label: Text(busy ? 'Saving…' : 'Confirm and save')),
            ],
          ],
        ]),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.hasKey, required this.useAi, required this.onToggle, required this.onSetup});
  final bool hasKey, useAi;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    if (!hasKey) {
      return SoftCard(
        onTap: onSetup,
        child: Row(children: [
          const IconBadge(icon: Icons.auto_awesome_rounded, color: AppColors.violet),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Want more accurate results?', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Add a free Gemini AI key in Settings (optional).', style: TextStyle(fontSize: 12.5)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.mutedText),
        ]),
      );
    }
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const IconBadge(icon: Icons.auto_awesome_rounded, color: AppColors.violet),
          title: const Text('Use Gemini AI', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Free, more accurate, reads any language'),
          value: useAi,
          onChanged: onToggle,
        ),
        Text(
          'With AI on, the photo is sent to Google. On Google\u2019s free tier, content may be used to improve their products. Turn it off to keep the photo on your phone.',
          style: TextStyle(fontSize: 12, color: context.mutedText),
        ),
      ]),
    );
  }
}
