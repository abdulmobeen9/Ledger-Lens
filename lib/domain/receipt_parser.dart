/// Free, fully offline receipt/transfer parser. It works on the text ML Kit reads on the device,
/// so there is no server, API key or per-scan cost. Results are heuristics: the scan screen always
/// lets the user review and correct every field before saving.
class AltAmount {
  const AltAmount(this.amount, this.currency, [this.label]);
  final double amount;
  final String currency;
  final String? label;
}

class ParsedReceipt {
  const ParsedReceipt({
    this.amount,
    this.currency,
    this.date,
    this.name,
    this.reference,
    this.receiving,
    this.method,
    this.fee,
    this.feeCurrency,
    this.exchangeRate,
    this.purpose,
    this.bank,
    this.extraReference,
    this.alternates = const [],
    required this.type,
    required this.confidence,
    this.readBy = 'offline',
  });

  final double? amount;
  final String? currency;
  final DateTime? date;
  final String? name, reference, receiving;
  final String? method; // bank | cash | wallet | card | null when unknown
  final double? fee;
  final String? feeCurrency;
  final double? exchangeRate;
  final String? purpose, bank;
  final String? extraReference; // e.g. MTCN / money-transfer control code
  final List<AltAmount> alternates; // other amounts shown, e.g. what the receiver gets in another currency
  final String type; // income | expense
  final double confidence; // 0..1
  final String readBy; // 'offline' (rules) or 'ai' (Gemini)
}

/// Uses [primary] and fills any field it left empty from [fallback].
ParsedReceipt mergeReceipts(ParsedReceipt primary, ParsedReceipt fallback) => ParsedReceipt(
      amount: primary.amount ?? fallback.amount,
      currency: primary.currency ?? fallback.currency,
      date: primary.date ?? fallback.date,
      name: primary.name ?? fallback.name,
      reference: primary.reference ?? fallback.reference,
      receiving: primary.receiving ?? fallback.receiving,
      method: primary.method ?? fallback.method,
      fee: primary.fee ?? fallback.fee,
      feeCurrency: primary.feeCurrency ?? fallback.feeCurrency,
      exchangeRate: primary.exchangeRate ?? fallback.exchangeRate,
      purpose: primary.purpose ?? fallback.purpose,
      bank: primary.bank ?? fallback.bank,
      extraReference: primary.extraReference ?? fallback.extraReference,
      alternates: primary.alternates.isNotEmpty ? primary.alternates : fallback.alternates,
      type: primary.type,
      confidence: primary.confidence,
      readBy: primary.readBy,
    );

String _plain(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

/// Extra details that have no dedicated field (fee, rate, purpose, transfer code, bank, other amounts),
/// written as one editable line for the transaction's notes.
String buildReceiptNotes(ParsedReceipt r) {
  final parts = <String>[];
  if (r.purpose != null) parts.add('Purpose: ${r.purpose}');
  if (r.fee != null) parts.add('Fee: ${r.feeCurrency ?? r.currency ?? ''} ${_plain(r.fee!)}'.replaceAll('  ', ' '));
  if (r.exchangeRate != null) parts.add('Rate: ${r.exchangeRate}');
  for (final a in r.alternates) {
    parts.add('${a.label ?? 'Also'}: ${a.currency} ${_plain(a.amount)}');
  }
  if (r.extraReference != null) parts.add('Transfer code: ${r.extraReference}');
  if (r.bank != null) parts.add('Bank: ${r.bank}');
  return parts.join(' • ');
}

const _currencyCodes = [
  'SAR', 'USD', 'EUR', 'GBP', 'INR', 'AED', 'KWD', 'QAR', 'BHD', 'OMR',
  'EGP', 'JOD', 'PKR', 'BDT', 'TRY', 'CAD', 'AUD', 'JPY', 'CNY', 'CHF',
  'NPR', 'LKR', 'PHP', 'MYR', 'SGD',
];

const _currencyAliases = <String, String>{
  r'$': 'USD',
  '€': 'EUR',
  '£': 'GBP',
  '₹': 'INR',
  '¥': 'JPY',
};

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final _dateIsoRe = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b');
final _dateDmyRe = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b');
final _dateNamedRe = RegExp(
  r'\b(\d{1,2})[ \-]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ ,\-]*(\d{4})\b',
  caseSensitive: false,
);
final _dateNamedUsRe = RegExp(
  r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? (\d{1,2}),? (\d{4})\b',
  caseSensitive: false,
);
final _timeRe = RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\s?(am|pm)?\b', caseSensitive: false);
final _numberRe = RegExp(r'(?<![\d.,])(\d{1,3}(?:[ ,]\d{3})+(?:[.,]\d{1,3})?|\d+(?:[.,]\d{1,3})?)(?!\d)');
final _referenceRe = RegExp(
  r'\b(?:ref(?:erence)?|txn|trx|transaction|rrn|invoice|inv|receipt|order|trace|stan|auth|control|tt)\s*(?:no\.?|number|id|code|#)?\s*[:#.\-]?\s*([A-Za-z0-9][A-Za-z0-9\-]{5,29})',
  caseSensitive: false,
);
final _ftRe = RegExp(r'\bFT\d{10,}\b');
final _mtcnRe = RegExp(r'\bmtcn\b\s*[:#\-]?\s*(\d{8,12})', caseSensitive: false);
final _phoneRe = RegExp(r'\+?\d[\d \-]{6,18}\d');
final _ibanLineRe = RegExp(r'(?<![A-Z0-9])[A-Z]{2}\d{2}(?: ?[A-Z0-9]){10,30}');

ParsedReceipt parseReceiptText(String raw, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final lower = raw.toLowerCase();

  final amountResult = _findAmount(lines);
  final date = _findDate(raw, today);
  final currency = _findCurrency(raw);
  final reference = _findReference(raw);
  final receiving = _findReceiving(lines, reference);
  final type = _findType(lower);
  final name = _findName(lines, type);
  final method = _findMethod(lower);

  var confidence = 0.15;
  if (amountResult.amount != null) confidence += amountResult.keyword ? 0.40 : 0.15;
  if (date != null) confidence += 0.15;
  if (currency != null) confidence += 0.10;
  if (reference != null || name != null) confidence += 0.10;
  if (confidence > 0.95) confidence = 0.95;

  return ParsedReceipt(
    amount: amountResult.amount,
    currency: currency,
    date: date,
    name: name,
    reference: reference,
    receiving: receiving,
    method: method,
    fee: _findFee(lines),
    exchangeRate: _findRate(lines),
    purpose: _clean(_labelValue(lines, _purposeRe)),
    bank: _clean(_labelValue(lines, _bankRe, allowLabelish: true)),
    extraReference: _mtcnRe.firstMatch(raw)?.group(1),
    type: type,
    confidence: confidence,
  );
}

// ---------------------------------------------------------------- amount

class _Amount {
  const _Amount(this.amount, this.keyword);
  final double? amount;
  final bool keyword;
}

const _strongKeywords = <String, double>{
  'grand total': 6,
  'total amount': 6,
  'amount due': 6,
  'amount paid': 5,
  'total paid': 5,
  'net total': 5,
  'net amount': 5,
  'total due': 5,
  'balance due': 5,
  'total': 4,
  'amount': 3,
  'paid': 2,
  'sum': 2,
};

final _penaltyRe = RegExp(
  r'\b(subtotal|sub total|sub-total|vat|tax|change|tendered|discount|qty|quantity|tel|phone|mobile|points|fee|fees|balance|cashback|rate|exchange|charge|charges|commission)\b',
  caseSensitive: false,
);

String _stripNoise(String line) =>
    line.replaceAll(_dateIsoRe, ' ').replaceAll(_dateDmyRe, ' ').replaceAll(_dateNamedRe, ' ').replaceAll(_timeRe, ' ');

double? _toNumber(String s) {
  var t = s.replaceAll(' ', '');
  final hasComma = t.contains(',');
  final hasDot = t.contains('.');
  if (hasComma && hasDot) {
    t = t.lastIndexOf(',') > t.lastIndexOf('.') ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else if (hasComma) {
    final parts = t.split(',');
    t = (parts.length == 2 && parts[1].length <= 2) ? '${parts[0]}.${parts[1]}' : t.replaceAll(',', '');
  } else if (hasDot && t.split('.').length > 2) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t);
}

List<double> _numbersIn(String line, {bool decimalsOnly = false}) {
  final out = <double>[];
  for (final m in _numberRe.allMatches(_stripNoise(line))) {
    final text = m.group(1)!;
    final value = _toNumber(text);
    if (value == null || value <= 0) continue;
    final hasDecimals = RegExp(r'[.,]\d{1,3}$').hasMatch(text) && !RegExp(r'^\d{1,3}(?:[ ,]\d{3})+$').hasMatch(text);
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (decimalsOnly && !hasDecimals) continue;
    if (!hasDecimals && digits.length >= 7) continue; // phone, account or reference numbers
    if (!hasDecimals && value >= 1900 && value <= 2100) continue; // probably a year
    out.add(value);
  }
  return out;
}

_Amount _findAmount(List<String> lines) {
  double bestScore = -100;
  double? best;
  var bestHasKeyword = false;

  double keywordScore(String lowerLine) {
    if (lowerLine.contains('subtotal') || lowerLine.contains('sub total') || lowerLine.contains('sub-total')) return -3;
    var score = 0.0;
    _strongKeywords.forEach((k, v) {
      if (lowerLine.contains(k) && v > score) score = v;
    });
    final penalised = _penaltyRe.hasMatch(lowerLine);
    if (score > 0 && penalised && !lowerLine.contains('total') && !lowerLine.contains('due')) score = 0;
    if (score == 0 && penalised) score = -3;
    return score;
  }

  for (var i = 0; i < lines.length; i++) {
    final lowerLine = lines[i].toLowerCase();
    var score = keywordScore(lowerLine);
    var numbers = _numbersIn(lines[i]);
    if (numbers.isEmpty && score > 0 && i + 1 < lines.length) {
      numbers = _numbersIn(lines[i + 1]); // the value is often on the next line
      score -= 0.5;
    }
    for (final value in numbers) {
      var s = score;
      if (RegExp(r'[A-Za-z$€£₹¥]').hasMatch(lines[i]) && score > 0) s += 0.3;
      s += i * 0.001;
      if (s > bestScore || (s == bestScore && best != null && value > best)) {
        bestScore = s;
        best = value;
        bestHasKeyword = score > 0;
      }
    }
  }

  if (best != null && bestHasKeyword) return _Amount(best, true);

  // No keyword line: fall back to the largest money-looking number (it must have decimals).
  double? largest;
  for (final line in lines) {
    if (_penaltyRe.hasMatch(line)) continue;
    for (final v in _numbersIn(line, decimalsOnly: true)) {
      if (largest == null || v > largest) largest = v;
    }
  }
  return _Amount(largest, false);
}

double? _findFee(List<String> lines) {
  final feeRe = RegExp(r'\b(fees?|charges?|commission)\b', caseSensitive: false);
  for (var i = 0; i < lines.length; i++) {
    final lowerLine = lines[i].toLowerCase();
    if (!feeRe.hasMatch(lowerLine) || lowerLine.contains('total')) continue;
    var numbers = _numbersIn(lines[i]);
    if (numbers.isEmpty && i + 1 < lines.length) numbers = _numbersIn(lines[i + 1]);
    for (final v in numbers) {
      if (v > 0) return v;
    }
  }
  return null;
}

double? _findRate(List<String> lines) {
  final value = _labelValue(lines, _rateRe, numeric: true);
  if (value == null) return null;
  final number = _toNumber(value.replaceAll(RegExp(r'[^\d.,]'), ''));
  return number != null && number > 0 ? number : null;
}

// ---------------------------------------------------------------- date

DateTime? _validDate(int y, int m, int d, DateTime now) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  if (date.month != m || date.day != d) return null;
  if (y < 2000 || date.isAfter(now.add(const Duration(days: 2)))) return null;
  return date;
}

DateTime? _findDate(String raw, DateTime now) {
  final iso = _dateIsoRe.firstMatch(raw);
  if (iso != null) {
    final d = _validDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!), now);
    if (d != null) return d;
  }
  final named = _dateNamedRe.firstMatch(raw);
  if (named != null) {
    final d = _validDate(int.parse(named.group(3)!), _months[named.group(2)!.toLowerCase()]!, int.parse(named.group(1)!), now);
    if (d != null) return d;
  }
  final us = _dateNamedUsRe.firstMatch(raw);
  if (us != null) {
    final d = _validDate(int.parse(us.group(3)!), _months[us.group(1)!.toLowerCase()]!, int.parse(us.group(2)!), now);
    if (d != null) return d;
  }
  for (final m in _dateDmyRe.allMatches(raw)) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    // Day-first unless the second number can only be a day (e.g. 11/21/2026).
    final dayFirst = b <= 12 || a > 12;
    final d = dayFirst ? _validDate(y, b, a, now) : _validDate(y, a, b, now);
    if (d != null) return d;
  }
  return null;
}

// ---------------------------------------------------------------- currency

String? _findCurrency(String raw) {
  final counts = <String, int>{};
  for (final code in _currencyCodes) {
    final n = RegExp('\\b$code\\b', caseSensitive: false).allMatches(raw).length;
    if (n > 0) counts[code] = n;
  }
  _currencyAliases.forEach((symbol, code) {
    final n = symbol.allMatches(raw).length;
    if (n > 0) counts[code] = (counts[code] ?? 0) + n;
  });
  const wordAliases = {
    r'\bS\.?R\.?\b': 'SAR',
    r'\bK\.?D\.?\b': 'KWD',
    r'\bQ\.?R\.?\b': 'QAR',
    r'\bB\.?D\.?\b': 'BHD',
    'ر\\.?س': 'SAR',
  };
  wordAliases.forEach((pattern, code) {
    final n = RegExp(pattern).allMatches(raw).length;
    if (n > 0) counts[code] = (counts[code] ?? 0) + n;
  });
  if (counts.isEmpty) return null;
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

// ---------------------------------------------------------------- text fields

String? _findReference(String raw) {
  // A keyword can be consumed by an earlier non-numeric match (e.g. "Receipt\nReference ..."),
  // so scan forward one character at a time instead of using allMatches.
  var pos = 0;
  while (pos < raw.length) {
    final m = _referenceRe.firstMatch(raw.substring(pos));
    if (m == null) break;
    final value = m.group(1)!;
    if (RegExp(r'\d').hasMatch(value) && value.length >= 6) return value;
    pos += m.start + 1;
  }
  return _ftRe.firstMatch(raw)?.group(0);
}

const _valueStoplist = {'details', 'detail', 'information', 'info', 'name', 'account', 'number', 'bank', 'branch'};
final _labelishRe = RegExp(r'\b(name|account|bank|branch|number|date|amount|details|status|type|code)\b', caseSensitive: false);

/// Finds "Label: value" or "Label" followed by its value on the next line.
String? _labelValue(List<String> lines, RegExp label, {bool numeric = false, bool allowLabelish = false}) {
  for (var i = 0; i < lines.length; i++) {
    final m = label.firstMatch(lines[i]);
    if (m == null) continue;
    var value = (m.group(1) ?? '').trim();
    if (_valueStoplist.contains(value.toLowerCase())) value = '';
    if (value.isNotEmpty) return value;
    if (i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      if (numeric) {
        if (RegExp(r'^\d[\d.,]*').hasMatch(next)) return next;
      } else if (RegExp(r'\p{L}{3,}', unicode: true).hasMatch(next) && (allowLabelish || !_labelishRe.hasMatch(next))) {
        return next;
      }
    }
  }
  return null;
}

final _payeeRe = RegExp(
  r"^(?:paid\s+to|transfer(?:red)?\s+to|sent\s+to|beneficiary(?:\s+full)?(?:\s+name)?|receiver[’']?s?(?:\s+name)?|recipient(?:\s+name)?|merchant(?:\s+name)?|payee|account\s+name|customer\s+name|to\s*[:\-])\s*[:\-]?\s*(.*)$",
  caseSensitive: false,
);
final _senderRe = RegExp(
  r"^(?:received\s+from|sender[’']?s?(?:\s+name)?|remitter(?:\s+name)?|from\s*[:\-])\s*[:\-]?\s*(.*)$",
  caseSensitive: false,
);
final _purposeRe = RegExp(r'^(?:purpose(?:\s+of\s+(?:transfer|remittance|payment))?|reason)\s*[:\-]?\s*(.*)$', caseSensitive: false);
final _bankRe = RegExp(r'^(?:beneficiary\s+)?bank(?:\s+name)?\s*[:\-]?\s*(.*)$', caseSensitive: false);
final _rateRe = RegExp(r'^(?:exchange\s+)?(?:rate|conversion\s+rate)\s*[:\-]?\s*(.*)$', caseSensitive: false);

const _ibanLengths = {
  'SA': 24, 'AE': 23, 'KW': 30, 'QA': 29, 'BH': 22, 'OM': 23, 'JO': 30, 'EG': 29, 'PK': 24, 'GB': 22,
  'DE': 22, 'FR': 27, 'ES': 24, 'IT': 27, 'NL': 18, 'TR': 26, 'IQ': 23, 'LB': 28,
};

String? _findReceiving(List<String> lines, String? reference) {
  // Only strings with a real IBAN country code and length count, so transaction numbers are not mistaken for IBANs.
  for (final line in lines) {
    final m = _ibanLineRe.firstMatch(line.toUpperCase());
    if (m == null) continue;
    final iban = m.group(0)!.replaceAll(' ', '');
    final expected = _ibanLengths[iban.substring(0, 2)];
    if (expected != null && iban.length >= expected && iban != reference) return iban.substring(0, expected);
  }
  String? digitsIn(String line) {
    final m = _phoneRe.firstMatch(line);
    if (m == null) return null;
    final digits = m.group(0)!.replaceAll(RegExp(r'[ \-]'), '');
    return digits.length >= 8 && digits != reference ? digits : null;
  }

  final senderRe = RegExp(r'\b(sender|from|initiator|remitter|payer)\b', caseSensitive: false);
  // First the receiver's account, then any other account/phone line (never the sender's).
  const passes = [
    ['receiver', 'recipient', 'beneficiary'],
    ['account', 'acct', 'mobile', 'phone', 'wallet', 'iban', 'to'],
  ];
  for (final keys in passes) {
    for (var i = 0; i < lines.length; i++) {
      final lowerLine = lines[i].toLowerCase();
      if (senderRe.hasMatch(lowerLine) || !keys.any((k) => RegExp('\\b$k\\b').hasMatch(lowerLine))) continue;
      var digits = digitsIn(lines[i]);
      // Layouts with the label on one line and the number on the next.
      if (digits == null && i + 1 < lines.length && !RegExp(r'\p{L}{3,}', unicode: true).hasMatch(lines[i + 1])) {
        digits = digitsIn(lines[i + 1]);
      }
      if (digits != null) return digits;
    }
  }
  return null;
}

String? _clean(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll(RegExp(r'[^\p{L}\p{N} .&\-/]', unicode: true), '').trim();
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(cleaned).length;
  if (letters < 3) return null;
  return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
}

String? _findName(List<String> lines, String type) {
  final order = type == 'income' ? [_senderRe, _payeeRe] : [_payeeRe];
  for (final re in order) {
    final name = _clean(_labelValue(lines, re));
    if (name != null) return name;
  }
  const skip = ['receipt', 'invoice', 'tax', 'vat', 'tel', 'phone', 'date', 'time', 'cashier', 'www', 'http', '@', 'welcome', 'thank', 'payment', 'transfer', 'transaction', 'success'];
  for (final line in lines.take(6)) {
    final lowerLine = line.toLowerCase();
    if (skip.any(lowerLine.contains)) continue;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(line).length;
    if (letters >= 3 && letters / line.length >= 0.6) return _clean(line);
  }
  return null;
}

String _findType(String lower) {
  const incoming = ['received from', 'you received', 'credited', 'credit alert', 'deposit', 'salary', 'incoming', 'refund'];
  const outgoing = ['paid to', 'sent to', 'transferred to', 'transfer to', 'debit', 'purchase', 'withdrawal', 'payment to'];
  final inc = incoming.any(lower.contains);
  final out = outgoing.any(lower.contains);
  return inc && !out ? 'income' : 'expense';
}

String? _findMethod(String lower) {
  bool any(List<String> keys) => keys.any((k) => RegExp('\\b$k\\b').hasMatch(lower));
  if (any(['stc pay', 'apple pay', 'paypal', 'google pay', 'gpay', 'paytm', 'upi', 'bkash', 'jazzcash', 'easypaisa', 'wallet'])) return 'wallet';
  if (any(['visa', 'mastercard', 'master card', 'mada', 'amex', 'pos', 'debit card', 'credit card'])) return 'card';
  if (any(['iban', 'swift', 'bank transfer', 'transfer', 'beneficiary', 'account no', 'account number'])) return 'bank';
  if (any(['cash'])) return 'cash';
  return null;
}
