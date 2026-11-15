import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/nav_controller.dart';
import '../controllers/tally_controller.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/cash_views.dart';
import '../widgets/common.dart';
import '../widgets/customer_filter_bar.dart';
import '../widgets/entry_dialog.dart';

double _sum(Iterable<Entry> l, double Function(Entry) f) =>
    l.fold(0.0, (s, e) => s + f(e));

/// Monday–Sunday view. Two layouts:
///  - Calendar: 7 day columns, each listing that day's entries
///  - Table:    one row per customer, sale and payment per day
/// The "Sales | Cash book" switch shows the week's cash book instead.
class WeeklyPage extends StatelessWidget {
  const WeeklyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final nav = Get.find<NavController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      final start = nav.weekStart.value;
      final days = List.generate(7, (i) => start.add(Duration(days: i)));
      final end = days.last;
      final cash = nav.calendarCash.value;
      // Customer / state / district filter (shared with Daily and Monthly)
      final ids = nav.calendarFilter.matchingIds(c.customers);
      final weekEntries = c.entries
          .where((e) =>
              !e.date.isBefore(start) &&
              !e.date.isAfter(end) &&
              (ids == null || ids.contains(e.customerId)))
          .toList();

      final weekSold = _sum(weekEntries, (e) => e.amount);
      final weekPaid = _sum(weekEntries, (e) => e.paid);

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Week selector -----
            Row(children: [
              Text('Weekly', style: t.headlineMedium),
              const SizedBox(width: 24),
              IconButton(
                tooltip: 'Previous week',
                onPressed: () =>
                    nav.weekStart.value = start.subtract(const Duration(days: 7)),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${shortDate(start)}  –  ${shortDate(end)}', style: t.titleMedium),
              IconButton(
                tooltip: 'Next week',
                onPressed: () => nav.weekStart.value = start.add(const Duration(days: 7)),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => nav.weekStart.value = weekStartOf(DateTime.now()),
                child: const Text('This week'),
              ),
              // Switches on the right. In a small window with a wider font
              // (e.g. Windows) they shrink a little instead of being cut off.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 12),
                      if (!cash) ...[
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: false,
                                icon: Icon(Icons.view_week),
                                label: Text('Calendar')),
                            ButtonSegment(
                                value: true,
                                icon: Icon(Icons.table_chart),
                                label: Text('Table')),
                          ],
                          selected: {nav.weekAsTable.value},
                          onSelectionChanged: (s) => nav.weekAsTable.value = s.first,
                        ),
                        const SizedBox(width: 12),
                      ],
                      const SalesCashSwitch(),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // ----- Cash book for this week -----
            if (cash) ...[
              CashAddButtons(date: dayToAddOn(start, end)),
              const SizedBox(height: 16),
              Expanded(
                child: CashPeriodView(
                    from: start, to: end, period: 'week', onOpenDay: nav.openDay),
              ),
            ] else ...[
              CustomerFilterBar(nav.calendarFilter),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                StatCard('Week sales', money(weekSold)),
                StatCard('Week received', money(weekPaid), color: PayStatus.green.color),
                StatCard('Week balance', money(weekSold - weekPaid),
                    color: PayStatus.red.color),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: nav.weekAsTable.value
                    ? _WeekTable(days: days, weekEntries: weekEntries, filtered: ids != null)
                    : _WeekCalendar(days: days, weekEntries: weekEntries),
              ),
            ],
          ],
        ),
      );
    });
  }
}

// =====================================================================
// Calendar layout: 7 columns, one per day
// =====================================================================

class _WeekCalendar extends StatelessWidget {
  final List<DateTime> days;
  final List<Entry> weekEntries;
  const _WeekCalendar({required this.days, required this.weekEntries});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in days)
          Expanded(
            child: _DayColumn(
              day: d,
              entries: weekEntries.where((e) => sameDay(e.date, d)).toList(),
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime day;
  final List<Entry> entries;
  const _DayColumn({required this.day, required this.entries});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final nav = Get.find<NavController>();
    final scheme = Theme.of(context).colorScheme;
    final isToday = sameDay(day, DateTime.now());
    final sold = _sum(entries, (e) => e.amount);
    final paid = _sum(entries, (e) => e.paid);

    entries.sort(
        (a, b) => c.customerName(a.customerId).compareTo(c.customerName(b.customerId)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5),
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----- Day header: click to open the day, + to add -----
          InkWell(
            onTap: () => nav.openDay(day),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('EEE').format(day),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isToday ? scheme.primary : null)),
                      Text(DateFormat('d MMM').format(day),
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Add entry on this day',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => openEntryDialog(date: day),
                ),
              ]),
            ),
          ),
          // Day totals
          Container(
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sale ${money(sold)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Paid ${money(paid)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PayStatus.green.color)),
              ],
            ),
          ),
          // ----- Entries -----
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text('No entries',
                        style: TextStyle(fontSize: 12, color: scheme.outline)))
                : ListView(
                    padding: const EdgeInsets.all(6),
                    children: [for (final e in entries) _EntryCard(e)],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Small card for one entry inside a day column. Click to edit.
class _EntryCard extends StatelessWidget {
  final Entry e;
  const _EntryCard(this.e);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    const small = TextStyle(fontSize: 11);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => openEntryDialog(entry: e),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(radius: 4, backgroundColor: c.statusOf(e.customerId).color),
                const SizedBox(width: 6),
                if (c.wasEdited(e.id))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: 'Edited – open the entry to see changes',
                      child: Icon(Icons.history, size: 12, color: Colors.blue.shade700),
                    ),
                  ),
                Expanded(
                  child: Text(c.customerName(e.customerId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ]),
              if (e.qty > 0) ...[
                const SizedBox(height: 2),
                Text(e.product.isEmpty ? '-' : e.product,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                Text('${kg(e.qty)} × ${perKg(e.rate)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                Text(money(e.amount),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
              if (e.paid > 0)
                Text('Paid ${paidText(e.paid, e.paymentMode)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PayStatus.green.color)),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Table layout: one row per customer
// =====================================================================

class _WeekTable extends StatelessWidget {
  final List<DateTime> days;
  final List<Entry> weekEntries;
  final bool filtered; // a customer / state / district filter is on
  const _WeekTable({required this.days, required this.weekEntries, required this.filtered});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final nav = Get.find<NavController>();

    // Only customers who bought or paid this week
    final ids = weekEntries.map((e) => e.customerId).toSet();
    final rowsCustomers = c.customers.where((cu) => ids.contains(cu.id)).toList();

    Widget cell(Iterable<Entry> l) {
      final sold = _sum(l, (e) => e.amount);
      final paid = _sum(l, (e) => e.paid);
      if (sold == 0 && paid == 0) return const Text('-');
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (sold > 0) Text(money(sold)),
          if (paid > 0)
            Text(money(paid),
                style: TextStyle(color: PayStatus.green.color, fontSize: 12)),
        ],
      );
    }

    if (rowsCustomers.isEmpty) {
      return Center(
          child: Text(filtered
              ? 'No sales or payments this week for the chosen customers.'
              : 'No sales or payments this week.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Black = sale, green = paid. Click a day to open it.',
            style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMinHeight: 52,
                dataRowMaxHeight: 60,
                columns: [
                  const DataColumn(label: Text('Customer')),
                  for (final d in days)
                    DataColumn(
                      numeric: true,
                      label: InkWell(
                        onTap: () => nav.openDay(d),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(DateFormat('EEE').format(d),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: sameDay(d, DateTime.now())
                                        ? Theme.of(context).colorScheme.primary
                                        : null)),
                            Text(DateFormat('d MMM').format(d),
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  const DataColumn(label: Text('Week total'), numeric: true),
                ],
                rows: [
                  for (final cu in rowsCustomers)
                    DataRow(cells: [
                      DataCell(Row(children: [
                        CircleAvatar(radius: 6, backgroundColor: c.statusOf(cu.id).color),
                        const SizedBox(width: 8),
                        Text(cu.label),
                      ])),
                      for (final d in days)
                        DataCell(cell(weekEntries
                            .where((e) => e.customerId == cu.id && sameDay(e.date, d)))),
                      DataCell(cell(weekEntries.where((e) => e.customerId == cu.id))),
                    ]),
                  // Totals row
                  DataRow(
                    color: WidgetStatePropertyAll(Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5)),
                    cells: [
                      const DataCell(
                          Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                      for (final d in days)
                        DataCell(cell(weekEntries.where((e) => sameDay(e.date, d)))),
                      DataCell(cell(weekEntries)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
