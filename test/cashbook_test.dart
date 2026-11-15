import 'package:flutter_test/flutter_test.dart';
import 'package:ghee_tally/models.dart';
import 'package:ghee_tally/services/cashbook.dart';

DateTime d(int day) => DateTime(2026, 11, day);

CashTxn txn(String type, int day, String account, double amount,
        {String to = '', String category = ''}) =>
    CashTxn(
        id: '$type$day$account$amount',
        type: type,
        date: d(day),
        account: account,
        toAccount: to,
        category: category,
        amount: amount);

Entry pay(int day, double paid, String mode) =>
    Entry(id: 'e$day$paid', customerId: 'c', date: d(day), paid: paid, paymentMode: mode);

String accountFor(String mode) => mode == 'Cash' || mode.isEmpty ? 'Cash' : 'Bank';

void main() {
  final entries = [
    pay(1, 5000, 'Cash'),
    pay(1, 20000, 'UPI'),
    pay(2, 3000, ''), // no mode -> Cash
  ];
  final txns = [
    txn(CashTxn.opening, 1, 'Cash', 10000), // counted when the shop opened on 1st
    txn(CashTxn.opening, 1, 'Bank', 50000),
    txn(CashTxn.expense, 1, 'Cash', 1200, category: 'EB (Electricity)'),
    txn(CashTxn.expense, 2, 'Bank', 8000, category: 'Rent'),
    txn(CashTxn.transfer, 2, 'Cash', 10000, to: 'Bank'), // cash deposited in bank
    txn(CashTxn.income, 3, 'Cash', 2000, category: 'Owner added money'),
    txn(CashTxn.opening, 3, 'Cash', 6500), // counted on 3rd: expected 6800 -> short 300
  ];
  List<CashDay> run(int from, int to) => cashBook(
        accounts: ['Cash', 'Bank'],
        movements: movementsFrom(entries, txns, accountFor),
        txns: txns,
        from: d(from),
        to: d(to),
      );

  test('day 1: counted opening, payments by mode, expense', () {
    final day1 = run(1, 1).single;
    final cash = day1.accounts['Cash']!;
    expect(cash.opening, 10000);
    expect(cash.moneyIn, 5000);
    expect(cash.moneyOut, 1200);
    expect(cash.closing, 13800);
    final bank = day1.accounts['Bank']!;
    expect(bank.closing, 70000); // 50000 + 20000 UPI
    expect(day1.closing, 83800);
  });

  test('day 2 starts from day 1 closing; transfer moves money', () {
    final day2 = run(2, 2).single;
    final cash = day2.accounts['Cash']!;
    expect(cash.counted, isNull);
    expect(cash.opening, 13800);
    expect(cash.moneyIn, 3000); // payment without a mode
    expect(cash.moneyOut, 10000); // deposited in bank
    expect(cash.closing, 6800);
    final bank = day2.accounts['Bank']!;
    expect(bank.moneyIn, 10000);
    expect(bank.moneyOut, 8000); // rent
    expect(bank.closing, 72000);
    expect(day2.closing, 78800); // transfer does not change the total
  });

  test('counted opening shows short / extra against the expected balance', () {
    final cash = run(3, 3).single.accounts['Cash']!;
    expect(cash.expected, 6800);
    expect(cash.counted, 6500);
    expect(cash.difference, -300); // short by 300
    expect(cash.closing, 8500); // 6500 + 2000 owner money
  });

  test('every calendar day is listed, quiet days carry the balance', () {
    final days = run(1, 5);
    expect(days.length, 5);
    expect(days[4].accounts['Cash']!.opening, 8500);
    expect(days[4].accounts['Cash']!.closing, 8500);
  });

  test('accounts used but not in the list are still shown', () {
    final days = cashBook(
      accounts: ['Cash'],
      movements: [Movement(d(1), 'Petty cash', 500)],
      txns: const [],
      from: d(1),
      to: d(1),
    );
    expect(days.single.accounts['Petty cash']!.closing, 500);
  });

  test('expenses by type, biggest first', () {
    final totals = totalsByCategory(txns.where((t) => t.type == CashTxn.expense));
    expect(totals.first.key, 'Rent');
    expect(totals.first.value, 8000);
  });

  test('totals for a period (week / month): first and last day count, '
      'transfers and opening balances do not', () {
    final all = cashTotals(entries, txns, d(1), d(3));
    expect(all.customerIn, 28000); // 5000 + 20000 + 3000
    expect(all.otherIn, 2000);
    expect(all.spent, 9200); // 1200 + 8000
    expect(all.net, 28000 + 2000 - 9200);

    final day2to3 = cashTotals(entries, txns, d(2), d(3));
    expect(day2to3.customerIn, 3000);
    expect(day2to3.otherIn, 2000);
    expect(day2to3.expenses.map((x) => x.category), ['Rent']);

    final empty = cashTotals(entries, txns, d(10), d(16));
    expect([empty.customerIn, empty.otherIn, empty.spent, empty.net], [0, 0, 0, 0]);
  });
}
