import 'package:csv/csv.dart';
import '../data/local/app_database.dart';

/// Neutralises spreadsheet formula injection: a text cell that starts with = + - @ (or tab/CR)
/// is prefixed with an apostrophe so Excel and Sheets treat it as text.
String? sanitizeCsvCell(String? value) {
  if (value == null || value.isEmpty) return value;
  const risky = {'=', '+', '-', '@', '\t', '\r'};
  return risky.contains(value[0]) ? "'$value" : value;
}

String buildTransactionsCsv(List<Transaction> rows, Map<String, String> categoryNames) {
  final data = <List<dynamic>>[
    ['Date', 'Type', 'Amount', 'Currency', 'Name', 'Category', 'Method', 'Reference', 'Receiving number', 'Notes'],
    for (final r in rows)
      [
        r.txnDate.toIso8601String().substring(0, 10),
        r.type,
        r.preciseAmount,
        r.currency,
        sanitizeCsvCell(r.counterpartyName),
        sanitizeCsvCell(categoryNames[r.categoryId] ?? ''),
        r.transferMethod,
        sanitizeCsvCell(r.referenceNo),
        sanitizeCsvCell(r.receivingNumber),
        sanitizeCsvCell(r.notes),
      ],
  ];
  return const ListToCsvConverter().convert(data);
}
