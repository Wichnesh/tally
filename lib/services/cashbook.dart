import '../models.dart';
import '../utils.dart';

/// One movement of money in or out of an account on a day.
class Movement {
  final DateTime date;
  final String account;
  final double amount; // positive = money in, negative = money out
  Movement(this.date, this.account, this.amount);
}

/// One account on one day:
///   opening (counted, or else yesterday's closing) + in - out = closing
class AccountDay {
  final String account;
  double expected = 0; // what the opening should be: the previous closing
  double? counted; // opening balance entered by the user, if any
  double moneyIn = 0;
  double moneyOut = 0;
  AccountDay(this.account);

  double get opening => counted ?? expected;
  double get closing => opening + moneyIn - moneyOut;

  /// Counted minus expected: negative = short, positive = extra.
  double? get difference => counted == null ? null : counted! - expected;
}

/// All accounts on one day.
class CashDay {
  final DateTime date;
  final Map<String, AccountDay> accounts;
  CashDay(this.date, this.accounts);

  double get opening => accounts.values.fold(0.0, (s, a) => s + a.opening);
  double get moneyIn => accounts.values.fold(0.0, (s, a) => s + a.moneyIn);
  double get moneyOut => accounts.values.fold(0.0, (s, a) => s + a.moneyOut);
  double get closing => accounts.values.fold(0.0, (s, a) => s + a.closing);
}

/// Turns customer payments and cash-book lines into movements.
/// [accountForMode] says which account a payment mode goes to
/// (e.g. Cash -> Cash, UPI -> Bank). Opening balances are not movements.
List<Movement> movementsFrom(Iterable<Entry> entries, Iterable<CashTxn> txns,
    String Function(String mode) accountForMode) {
  return [
    for (final e in entries)
      if (e.paid > 0) Movement(e.date, accountForMode(e.paymentMode), e.paid),
    for (final t in txns)
      ...switch (t.type) {
        CashTxn.expense => [Movement(t.date, t.account, -t.amount)],
        CashTxn.income => [Movement(t.date, t.account, t.amount)],
        CashTxn.transfer => [
            Movement(t.date, t.account, -t.amount),
            Movement(t.date, t.toAccount, t.amount),
          ],
        _ => <Movement>[],
      },
  ];
}

/// Works out every day from [from] to [to] (inclusive) for each account.
///
/// The balance runs from the very first movement: each day starts with the
/// previous day's closing. If an opening balance was entered for that day
/// (in [txns], type 'opening'), the day starts from that amount instead and
/// the difference is shown as short / extra.
List<CashDay> cashBook({
  required List<String> accounts,
  required List<Movement> movements,
  required Iterable<CashTxn> txns,
  required DateTime from,
  required DateTime to,
}) {
  from = dateOnly(from);
  to = dateOnly(to);

  // Opening balances: account -> day -> amount (the last one entered wins)
  final counts = <String, Map<DateTime, double>>{};
  for (final t in txns.where((t) => t.type == CashTxn.opening)) {
    counts.putIfAbsent(t.account, () => {})[dateOnly(t.date)] = t.amount;
  }

  // Every account in use, even one no longer in the list
  final names = <String>{
    ...accounts,
    for (final m in movements) m.account,
    ...counts.keys,
  }.toList();

  // Movements per day
  final byDay = <DateTime, List<Movement>>{};
  for (final m in movements) {
    byDay.putIfAbsent(dateOnly(m.date), () => []).add(m);
  }

  final balance = {for (final a in names) a: 0.0};

  AccountDay run(DateTime day, String account) {
    final d = AccountDay(account)
      ..expected = balance[account]!
      ..counted = counts[account]?[day];
    for (final m in byDay[day] ?? const <Movement>[]) {
      if (m.account != account) continue;
      if (m.amount >= 0) {
        d.moneyIn += m.amount;
      } else {
        d.moneyOut += -m.amount;
      }
    }
    balance[account] = d.closing;
    return d;
  }

  // 1. Everything before [from], to get the starting balances
  final earlier = <DateTime>{
    ...byDay.keys.where((d) => d.isBefore(from)),
    for (final c in counts.values) ...c.keys.where((d) => d.isBefore(from)),
  }.toList()
    ..sort();
  for (final day in earlier) {
    for (final a in names) {
      run(day, a);
    }
  }

  // 2. Every calendar day in the range
  final days = <CashDay>[];
  for (var day = from; !day.isAfter(to); day = DateTime(day.year, day.month, day.day + 1)) {
    days.add(CashDay(day, {for (final a in names) a: run(day, a)}));
  }
  return days;
}

/// Total per category (expenses or money in), biggest first.
List<MapEntry<String, double>> totalsByCategory(Iterable<CashTxn> txns) {
  final map = <String, double>{};
  for (final t in txns) {
    final name = t.category.isEmpty ? 'Other' : t.category;
    map[name] = (map[name] ?? 0) + t.amount;
  }
  return map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Money in and out over a period (a week, a month…).
class CashTotals {
  final double customerIn; // customer payments
  final double otherIn; // other money in (owner added money, loan…)
  final List<CashTxn> expenses;
  CashTotals(this.customerIn, this.otherIn, this.expenses);

  double get spent => expenses.fold(0.0, (s, x) => s + x.amount);
  double get net => customerIn + otherIn - spent;
}

/// Totals for the days [from]..[to] (inclusive). Transfers and opening
/// balances are not money in or out, so they are not counted.
CashTotals cashTotals(
    Iterable<Entry> entries, Iterable<CashTxn> txns, DateTime from, DateTime to) {
  from = dateOnly(from);
  to = dateOnly(to);
  bool inRange(DateTime d) => !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);
  return CashTotals(
    entries.where((e) => inRange(e.date)).fold(0.0, (s, e) => s + e.paid),
    txns
        .where((x) => x.type == CashTxn.income && inRange(x.date))
        .fold(0.0, (s, x) => s + x.amount),
    txns.where((x) => x.type == CashTxn.expense && inRange(x.date)).toList(),
  );
}
