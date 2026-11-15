import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../utils.dart';
import 'customer_filter.dart';

enum Period { today, thisWeek, thisMonth, lastMonth, allTime, custom }

extension PeriodX on Period {
  String get label => switch (this) {
        Period.today => 'Today',
        Period.thisWeek => 'This week',
        Period.thisMonth => 'This month',
        Period.lastMonth => 'Last month',
        Period.allTime => 'All time',
        Period.custom => 'Choose dates',
      };
}

/// The Dashboard's filter choices.
class DashboardController extends GetxController {
  final period = Period.thisMonth.obs;
  final customFrom = Rxn<DateTime>();
  final customTo = Rxn<DateTime>();
  final customers = CustomerFilter(); // customer / state / district
  final products = <String>{}.obs; // empty = all products
  final modes = <String>{}.obs; // empty = all payment modes

  /// Start and end date of the chosen period (null = no limit).
  (DateTime?, DateTime?) get range {
    final now = dateOnly(DateTime.now());
    return switch (period.value) {
      Period.today => (now, now),
      Period.thisWeek => (weekStartOf(now), weekStartOf(now).add(const Duration(days: 6))),
      Period.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1, 0)),
      Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
      Period.allTime => (null, null),
      Period.custom => (customFrom.value, customTo.value),
    };
  }

  /// e.g. "1 Nov 2026 – 30 Nov 2026"
  String get rangeText {
    final (from, to) = range;
    if (from == null && to == null) return 'All dates';
    final f = DateFormat('d MMM yyyy');
    if (from != null && to != null && sameDay(from, to)) return f.format(from);
    return '${from == null ? '…' : f.format(from)}  –  ${to == null ? '…' : f.format(to)}';
  }

  bool get isFiltered =>
      period.value != Period.thisMonth ||
      customers.isActive ||
      products.isNotEmpty ||
      modes.isNotEmpty;

  void toggle(RxSet<String> set, String value) =>
      set.contains(value) ? set.remove(value) : set.add(value);

  void reset() {
    period.value = Period.thisMonth;
    customers.reset();
    products.clear();
    modes.clear();
  }
}
