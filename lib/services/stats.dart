import '../models.dart';

/// Totals for one product.
class ProductStat {
  final String product;
  double qty = 0; // kg
  double amount = 0; // ₹ sales
  int count = 0; // number of sale entries
  ProductStat(this.product);

  double get avgRate => qty == 0 ? 0 : amount / qty;
}

/// Totals for one payment mode.
class ModeStat {
  final String mode;
  double amount = 0; // ₹ received
  int count = 0; // number of payments
  ModeStat(this.mode);
}

const notSet = 'Not set';

/// Entries between [from] and [to] (inclusive, either can be null = open),
/// optionally only for one customer, or for a set of customers
/// ([customerIds] null = everyone).
List<Entry> entriesInRange(Iterable<Entry> all,
        {DateTime? from, DateTime? to, String? customerId, Set<String>? customerIds}) =>
    all
        .where((e) =>
            (from == null || !e.date.isBefore(from)) &&
            (to == null || !e.date.isAfter(to)) &&
            (customerId == null || e.customerId == customerId) &&
            (customerIds == null || customerIds.contains(e.customerId)))
        .toList();

/// Sales per product, biggest first. [only] empty = all products.
List<ProductStat> productStats(Iterable<Entry> entries, {Set<String> only = const {}}) {
  final map = <String, ProductStat>{};
  for (final e in entries) {
    if (e.qty <= 0) continue;
    final name = e.product.isEmpty ? notSet : e.product;
    if (only.isNotEmpty && !only.contains(name)) continue;
    final s = map.putIfAbsent(name, () => ProductStat(name));
    s.qty += e.qty;
    s.amount += e.amount;
    s.count++;
  }
  return map.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
}

/// Money received per payment mode, biggest first. [only] empty = all modes.
List<ModeStat> modeStats(Iterable<Entry> entries, {Set<String> only = const {}}) {
  final map = <String, ModeStat>{};
  for (final e in entries) {
    if (e.paid <= 0) continue;
    final name = e.paymentMode.isEmpty ? notSet : e.paymentMode;
    if (only.isNotEmpty && !only.contains(name)) continue;
    final s = map.putIfAbsent(name, () => ModeStat(name));
    s.amount += e.paid;
    s.count++;
  }
  return map.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
}
