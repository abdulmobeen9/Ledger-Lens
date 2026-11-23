import '../data/local/app_database.dart';
import 'analytics.dart';

class DuplicateMatch {
  const DuplicateMatch(this.transaction, this.reason, {required this.exact});
  final Transaction transaction;
  final String reason;

  /// True when a reference number or transfer code matched; false for a same-amount/date/name guess.
  final bool exact;
}

final _stripRe = RegExp(r'[\s\p{P}]', unicode: true);
String _norm(String? value) => (value ?? '').toLowerCase().replaceAll(_stripRe, '');

/// Looks for an already-saved copy of the same slip.
/// Exact: same reference number, or same transfer code (e.g. Western Union MTCN) in the reference or notes.
/// Possible: same amount, currency and day plus the same name or receiving account.
DuplicateMatch? findDuplicate(
  Iterable<Transaction> existing, {
  String? reference,
  String? transferCode,
  double? amount,
  String? currency,
  DateTime? date,
  String? name,
  String? receiving,
  String? excludeId,
}) {
  final ref = _norm(reference);
  final code = _norm(transferCode);
  final nameKey = _norm(name);
  final receivingKey = _norm(receiving);
  final minor = (amount != null && currency != null) ? amountToMinorUnits(amount, currency) : null;
  DuplicateMatch? possible;

  for (final t in existing) {
    if (t.id == excludeId) continue;
    final savedRef = _norm(t.referenceNo);
    final savedNotes = _norm(t.notes);
    if (ref.length >= 6 && (savedRef == ref || (savedNotes.contains(ref) && ref.length >= 8))) {
      return DuplicateMatch(t, 'the same reference number', exact: true);
    }
    if (code.length >= 8 && (savedRef == code || savedNotes.contains(code))) {
      return DuplicateMatch(t, 'the same transfer code', exact: true);
    }
    if (possible == null && minor != null && date != null && t.currency == currency && t.amountMinor == minor && sameDay(t.txnDate, date)) {
      final sameName = nameKey.isNotEmpty && _norm(t.counterpartyName) == nameKey;
      final sameReceiving = receivingKey.length >= 6 && _norm(t.receivingNumber) == receivingKey;
      if (sameName || sameReceiving) {
        possible = DuplicateMatch(t, sameName ? 'the same amount, date and name' : 'the same amount, date and receiving account', exact: false);
      }
    }
  }
  return possible;
}
