import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/domain/receipt_parser.dart';

void main() {
  final now = DateTime(2026, 11, 22);

  test('shop receipt: picks the total, not subtotal, VAT, cash or change', () {
    const text = 'BIG MART\nTel: 0112345678\nDate: 21/11/2026 14:32\nItem A 10.00\nItem B 5.50\nSubtotal 15.50\nVAT 15% 2.33\nTotal 17.83\nCash 20.00\nChange 2.17';
    final r = parseReceiptText(text, now: now);
    expect(r.amount, 17.83);
    expect(r.date, DateTime(2026, 11, 21));
    expect(r.name, 'BIG MART');
    expect(r.type, 'expense');
    expect(r.method, 'cash');
  });

  test('bank transfer: amount, currency, payee, reference, IBAN, date', () {
    const text = 'Transfer Successful\nAmount: SAR 1,250.00\nTo: Ahmed Ali\nReference No: TRX123456789\nIBAN SA0380000000608010167519\nDate 2026-11-20';
    final r = parseReceiptText(text, now: now);
    expect(r.amount, 1250.0);
    expect(r.currency, 'SAR');
    expect(r.name, 'Ahmed Ali');
    expect(r.reference, 'TRX123456789');
    expect(r.receiving, 'SA0380000000608010167519');
    expect(r.date, DateTime(2026, 11, 20));
    expect(r.method, 'bank');
    expect(r.confidence, greaterThan(0.7));
  });

  test('comma decimal separator is understood', () {
    final r = parseReceiptText('Shop\nTOTAL 45,50 EUR', now: now);
    expect(r.amount, 45.5);
    expect(r.currency, 'EUR');
  });

  test('month-first dates are detected when the day cannot be second', () {
    expect(parseReceiptText('Total 5.00\n11/21/2026', now: now).date, DateTime(2026, 11, 21));
    expect(parseReceiptText('Total 5.00\n03/04/2026', now: now).date, DateTime(2026, 4, 3));
  });

  test('incoming money is classified as income', () {
    final r = parseReceiptText('You received\nAmount 300.00\nReceived from: Sara Omar', now: now);
    expect(r.type, 'income');
    expect(r.name, 'Sara Omar');
  });

  test('unreadable input gives low confidence instead of guesses', () {
    final r = parseReceiptText('hello world', now: now);
    expect(r.amount, isNull);
    expect(r.confidence, lessThan(0.4));
  });

  group('remittance receipts (Nepal / Saudi / Kuwait)', () {
    test('Nepal Bank payment receipt: total, fee, receiver, reference, date', () {
      const text = 'Payment Receipt\nReference Code 70203036\nTxn Amount (NPR) 40,100.00\nCharge (NPR) 10.00\nTotal Amount (NPR) 40,110.00\n'
          "Sender's Name ********* AMAR\nSender's Account 051###558417000001\nReceiver's Name ***** MATEEN\nReceiver's Account 209###92347001\n"
          'Date/Time 16 Jun 2026,02:30 PM\nInitiator 9817806014';
      final r = parseReceiptText(text, now: now);
      expect(r.amount, 40110);
      expect(r.currency, 'NPR');
      expect(r.fee, 10);
      expect(r.name, 'MATEEN');
      expect(r.reference, '70203036');
      expect(r.receiving, '92347001');
      expect(r.date, DateTime(2026, 6, 16));
    });

    test('label-above-value layout (wallet app) with no amount shown', () {
      const text = 'Reference Number\n33TF000532446\nDate & Time\n03:08 AM, 07 Feb 2025\nPayment Method\nBasic Wallet Account\n'
          'Exchange Rate\n23.1636\nPurpose\nFAMILY MAINTENANCE\nBeneficiary Full Name\nMd Naushad Alam\n'
          'Bank Name\nPUNJAB NATIONAL BANK\nAccount Number\n4743001500010722';
      final r = parseReceiptText(text, now: now);
      expect(r.amount, isNull); // never guesses an amount that is not on the slip
      expect(r.reference, '33TF000532446');
      expect(r.date, DateTime(2025, 2, 7));
      expect(r.name, 'Md Naushad Alam');
      expect(r.receiving, '4743001500010722');
      expect(r.purpose, 'FAMILY MAINTENANCE');
      expect(r.bank, 'PUNJAB NATIONAL BANK');
      expect(r.exchangeRate, 23.1636);
      expect(r.method, 'wallet');
    });

    test('utility payment: amount in NPR, zero fee ignored, customer name', () {
      const text = 'MORU\nYour Transaction is Successful\nCustomer Name : ALI HUSEN NADAF\nSc No : 003.19.070\nCustomer Id : 4730\nAmount : NPR 31.0\nNEA Fee : 0.0';
      final r = parseReceiptText(text, now: now);
      expect(r.amount, 31);
      expect(r.currency, 'NPR');
      expect(r.name, 'ALI HUSEN NADAF');
      expect(r.fee, isNull);
    });

    test('telex transfer voucher: KWD total, commission and TT number', () {
      const text = 'AL ZAHRA (158)\nTELEX TRANSFER VOUCHER (KNET)\nTT Number 241587088481\nNPR 207,183.83\nRate 0.002281790\nCommission 1.250\nTotal in KWD 474.000\nKNet 474.000';
      final r = parseReceiptText(text, now: now);
      expect(r.amount, 474);
      expect(r.fee, 1.25);
      expect(r.reference, '241587088481');
    });

    test('notes line collects fee, rate, other amount and transfer code', () {
      const r = ParsedReceipt(
        amount: 7502,
        currency: 'SAR',
        fee: 17.25,
        feeCurrency: 'SAR',
        exchangeRate: 37.0046928,
        extraReference: '4305707068',
        alternates: [AltAmount(277609.21, 'NPR', 'Receiver gets')],
        type: 'expense',
        confidence: 0.9,
      );
      expect(buildReceiptNotes(r), 'Fee: SAR 17.25 • Rate: 37.0046928 • Receiver gets: NPR 277609.21 • Transfer code: 4305707068');
    });
  });
}
