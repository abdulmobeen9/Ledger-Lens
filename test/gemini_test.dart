import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/data/remote/gemini_service.dart';
import 'package:ledgerlens/domain/receipt_parser.dart';

Map<String, dynamic> model(String id, {List<String> methods = const ['generateContent']}) =>
    {'name': 'models/$id', 'supportedGenerationMethods': methods};

void main() {
  final now = DateTime(2026, 11, 22);

  group('model discovery', () {
    test('prefers the newest stable Flash model and skips image/preview/embedding models', () {
      final id = chooseGeminiModel([
        model('gemini-2.5-flash'),
        model('gemini-3-flash-preview'),
        model('gemini-3-flash'),
        model('gemini-3-flash-image'),
        model('text-embedding-004', methods: ['embedContent']),
      ]);
      expect(id, 'gemini-3-flash');
    });

    test('uses the Google-maintained latest alias when it is offered', () {
      expect(chooseGeminiModel([model('gemini-3-flash'), model('gemini-flash-latest')]), 'gemini-flash-latest');
    });

    test('returns null when no Flash model supports generateContent', () {
      expect(chooseGeminiModel([model('gemini-3-pro'), model('gemini-3-flash', methods: ['embedContent'])]), isNull);
    });
  });

  group('response parsing', () {
    test('parses fenced JSON and sanitises every field', () {
      final response = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'thought': true, 'text': 'ignored reasoning'},
                {
                  'text': '```json\n{"date":"2026-11-20","name":"Cafe\\nBar","transfer_method":"card","reference_no":null,'
                      '"receiving_number":null,"total_amount":"1,250.50","currency":"sar","type":"expense","confidence":1.7}\n```',
                },
              ],
            },
          },
        ],
      };
      final r = parseGeminiResponse(response, now: now);
      expect(r.amount, 1250.5);
      expect(r.currency, 'SAR');
      expect(r.date, DateTime(2026, 11, 20));
      expect(r.name, 'Cafe Bar');
      expect(r.method, 'card');
      expect(r.confidence, 1.0);
      expect(r.readBy, 'ai');
    });

    test('rejects invalid values instead of trusting the model', () {
      final r = sanitizeAiReceipt({
        'total_amount': -5,
        'currency': 'SARX',
        'date': '2031-01-01',
        'transfer_method': 'crypto',
        'type': 'weird',
        'name': 'x' * 500,
        'confidence': 'high',
      }, now: now);
      expect(r.amount, isNull);
      expect(r.currency, isNull);
      expect(r.date, isNull);
      expect(r.method, isNull);
      expect(r.type, 'expense');
      expect(r.name!.length, lessThanOrEqualTo(120));
      expect(r.confidence, 0.5);
    });

    test('an empty or blocked response is reported clearly', () {
      expect(() => parseGeminiResponse({'candidates': []}), throwsA(isA<GeminiException>()));
      expect(() => parseGeminiResponse({'candidates': [{'content': {'parts': [{'text': 'not json'}]}}]}), throwsFormatException);
    });
  });

  test('merge keeps AI values and fills gaps from the offline reader', () {
    const ai = ParsedReceipt(amount: 50, name: null, type: 'expense', confidence: 0.9, readBy: 'ai');
    const offline = ParsedReceipt(amount: 49, name: 'Corner Shop', reference: 'TRX998877', type: 'expense', confidence: 0.4);
    final merged = mergeReceipts(ai, offline);
    expect(merged.amount, 50);
    expect(merged.name, 'Corner Shop');
    expect(merged.reference, 'TRX998877');
    expect(merged.readBy, 'ai');
    expect(merged.confidence, 0.9);
  });

  test('remittance slip: other amounts, fee, rate and transfer code are kept; duplicates and bad values dropped', () {
    final r = sanitizeAiReceipt({
      'date': '2025-03-01',
      'name': 'Md Haroon Rain',
      'transfer_method': 'bank',
      'reference_no': 'FT25060898016591',
      'secondary_reference': '4305707068',
      'receiving_number': '425530996410008',
      'total_amount': 7502,
      'currency': 'SAR',
      'alternate_amounts': [
        {'amount': 277609.21, 'currency': 'npr', 'label': 'Receiver gets'},
        {'amount': 7502, 'currency': 'SAR', 'label': 'duplicate of the main amount'},
        {'amount': -1, 'currency': 'NPR', 'label': 'invalid'},
      ],
      'fee': 17.25,
      'fee_currency': 'SAR',
      'exchange_rate': 37.0046928,
      'type': 'expense',
      'confidence': 0.93,
    }, now: now);
    expect(r.amount, 7502);
    expect(r.alternates, hasLength(1));
    expect(r.alternates.single.currency, 'NPR');
    expect(r.alternates.single.amount, 277609.21);
    expect(r.fee, 17.25);
    expect(r.exchangeRate, 37.0046928);
    expect(r.extraReference, '4305707068');
    expect(r.reference, 'FT25060898016591');
  });
}
