class LedgerTransaction {
  const LedgerTransaction({required this.id, required this.userId, required this.type,
    required this.amount, required this.currency, required this.date, this.name,
    this.transferMethod, this.referenceNo, this.receivingNumber, this.categoryId,
    this.notes, this.imageUrl, this.ocrRawText, this.ocrConfidence, this.source = 'manual'});
  final String id, userId, type, currency;
  final double amount;
  final DateTime date;
  final String? name, transferMethod, referenceNo, receivingNumber, categoryId, notes, imageUrl, ocrRawText;
  final double? ocrConfidence;
  final String source;
}
