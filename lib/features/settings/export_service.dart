import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/providers.dart';
import '../../core/widgets.dart';
import '../../domain/csv_export.dart';

/// Writes all of the signed-in user's transactions to a CSV file and opens the share sheet.
Future<void> exportTransactionsCsv(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(supabaseProvider).auth.currentUser?.id;
  if (uid == null) return;
  try {
    final db = ref.read(databaseProvider);
    final rows = await db.transactionDao.getAll(uid);
    if (rows.isEmpty) {
      if (context.mounted) showSnack(context, 'There are no transactions to export yet.');
      return;
    }
    final categories = await db.categoryDao.getForUser(uid);
    final csv = buildTransactionsCsv(rows, {for (final c in categories) c.id: c.name});
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File(p.join(dir.path, 'ledgerlens-transactions-$stamp.csv'));
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: 'LedgerLens transactions');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Export failed: $e');
  }
}
