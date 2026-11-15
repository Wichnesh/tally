import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ---------- Formatting helpers ----------

final _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _qty = NumberFormat('#,##0.##', 'en_IN');

/// 100000 -> ₹1,00,000
String money(num v) => _money.format(v);

final _money2 =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Exact amount: ₹520 or ₹497.74 (paise only when there are any).
String moneyExact(num v) {
  final r = (v * 100).roundToDouble() / 100;
  return r == r.roundToDouble() ? money(r) : _money2.format(r);
}

/// Price per kg: ₹520 or ₹497.74.
String perKg(num v) => moneyExact(v);

/// Price per kg from the formula: percent × rate ÷ divisor, to the paisa.
/// e.g. 82.5 × 8000 ÷ 1326 = 497.74
double priceFromFormula(double percent, double rate, double divisor) =>
    divisor <= 0 ? 0 : (percent * rate / divisor * 100).roundToDouble() / 100;

/// 82.5 -> "82.5%"
String pctText(double v) => '${numText(v)}%';

/// "82.5% × ₹8,000" when a price came from the formula, else ''.
String formulaText(double? percent, double? baseRate) =>
    percent == null || baseRate == null ? '' : '${pctText(percent)} × ${money(baseRate)}';

/// Paid amount with payment mode, e.g. "₹5,000 · UPI" ("-" if nothing paid).
String paidText(double paid, String mode) {
  if (paid == 0) return '-';
  return mode.isEmpty ? money(paid) : '${money(paid)} · $mode';
}

/// 12.5 -> 12.5 kg
String kg(num v) => '${_qty.format(v)} kg';

/// 250.0 -> "250", 250.5 -> "250.5" (for text fields)
String numText(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

double parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of the week that contains [d]
DateTime weekStartOf(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - 1));

String longDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
String shortDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

// ---------- Payment status (Red / Yellow / Green) ----------

enum PayStatus { red, yellow, green, none }

extension PayStatusX on PayStatus {
  Color get color => switch (this) {
        PayStatus.red => const Color(0xFFD32F2F),
        PayStatus.yellow => const Color(0xFFF9A825),
        PayStatus.green => const Color(0xFF2E7D32),
        PayStatus.none => Colors.grey,
      };

  String get label => switch (this) {
        PayStatus.red => 'Red alert',
        PayStatus.yellow => 'Watch',
        PayStatus.green => 'Good',
        PayStatus.none => 'No sales',
      };
}
