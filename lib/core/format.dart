import 'package:intl/intl.dart';
import '../data/local/app_database.dart';

class Money {
  static const mask = '••••';

  static int digits(String currency) {
    final factor = currencyMinorUnitFactor(currency);
    return factor == 1000 ? 3 : (factor == 1 ? 0 : 2);
  }

  /// "SAR 1,250.00". Negative values use a true minus sign; [signed] adds "+" to positives.
  static String format(double value, String currency, {bool signed = false, bool hide = false}) {
    if (hide) return mask;
    final formatter = NumberFormat.currency(name: currency, symbol: '$currency ', decimalDigits: digits(currency));
    final text = formatter.format(value.abs());
    if (value < 0) return '−$text';
    if (signed && value > 0) return '+$text';
    return text;
  }

  static String compact(double value) => NumberFormat.compact().format(value);

  static String percent(double ratio) => '${(ratio * 100).round()}%';
}

class Dates {
  static String month(DateTime d) => DateFormat.yMMMM().format(d);
  static String monthShort(DateTime d) => DateFormat.MMM().format(d);
  static String day(DateTime d) => DateFormat.MMMd().format(d);
  static String dayLong(DateTime d) => DateFormat.yMMMMd().format(d);
  static String dayHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(d);
  }

  static String relative(DateTime? when) {
    if (when == null) return 'Not synced yet';
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  static String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

const List<String> kCurrencies = [
  'SAR', 'USD', 'EUR', 'GBP', 'INR', 'AED', 'KWD', 'QAR', 'BHD', 'OMR',
  'EGP', 'JOD', 'PKR', 'BDT', 'TRY', 'CAD', 'AUD', 'JPY', 'CNY', 'CHF',
  'NPR', 'LKR', 'PHP', 'MYR', 'SGD',
];
