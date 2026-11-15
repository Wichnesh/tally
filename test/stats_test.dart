import 'package:flutter_test/flutter_test.dart';
import 'package:ghee_tally/models.dart';
import 'package:ghee_tally/services/stats.dart';

Entry e(String day, String product, double qty, double rate, double paid, String mode,
        [String customer = 'a']) =>
    Entry(id: '$day$product$paid', customerId: customer, date: DateTime.parse(day),
        product: product, qty: qty, rate: rate, paid: paid, paymentMode: mode);

void main() {
  final entries = [
    e('2026-11-01', 'Yellow Ghee', 10, 500, 3000, 'UPI'),
    e('2026-11-02', 'Yellow Ghee', 5, 520, 0, ''),
    e('2026-11-02', 'Curd', 20, 60, 1200, 'Cash'),
    e('2026-11-03', '', 0, 0, 2000, 'UPI', 'b'), // payment only
    e('2026-10-30', 'Curd', 4, 60, 0, ''), // last month
  ];

  test('date range and customer filter', () {
    final nov = entriesInRange(entries,
        from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    expect(nov.length, 4);
    expect(entriesInRange(nov, customerId: 'b').length, 1);
    expect(entriesInRange(nov, customerIds: {'a'}).length, 3);
    expect(entriesInRange(nov, customerIds: {}).length, 0); // nobody matches
    expect(entriesInRange(nov, customerIds: null).length, 4); // no filter
  });

  test('sales by product', () {
    final nov = entriesInRange(entries, from: DateTime(2026, 11, 1));
    final stats = productStats(nov);
    expect(stats.map((s) => s.product), ['Yellow Ghee', 'Curd']); // biggest first
    final ghee = stats.first;
    expect(ghee.qty, 15);
    expect(ghee.amount, 7600); // 10x500 + 5x520
    expect(ghee.count, 2);
    expect(ghee.avgRate.toStringAsFixed(2), '506.67');
    // Only selected products
    expect(productStats(nov, only: {'Curd'}).single.amount, 1200);
  });

  test('payments by mode', () {
    final stats = modeStats(entries);
    expect(stats.first.mode, 'UPI');
    expect(stats.first.amount, 5000);
    expect(stats.first.count, 2);
    expect(stats.firstWhere((s) => s.mode == 'Cash').amount, 1200);
    expect(modeStats(entries, only: {'Cash'}).single.amount, 1200);
    // Payments without a mode are grouped as "Not set"
    final withNoMode = [e('2026-11-05', '', 0, 0, 700, '')];
    expect(modeStats(withNoMode).single.mode, notSet);
  });
}
