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

/// Month calendar. Each day shows sales, money received and ghee sold.
/// Click a day to open it in the Daily screen.
/// The "Sales | Cash book" switch shows the month's cash book instead.
class MonthlyPage extends StatelessWidget {
  const MonthlyPage({super.key});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _minRowHeight = 80.0;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final nav = Get.find<NavController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      final month = nav.month.value; // 1st of the month
      final nextMonth = DateTime(month.year, month.month + 1);
      final daysInMonth = nextMonth.difference(month).inDays;
      final lastDay = DateTime(month.year, month.month + 1, 0);
      final cash = nav.calendarCash.value;

      // Calendar starts on the Monday on/before the 1st
      final gridStart = weekStartOf(month);
      final weeks = ((month.weekday - 1 + daysInMonth) / 7).ceil();

      // Entries of this month, grouped by day
      // Customer / state / district filter (shared with Daily and Weekly)
      final ids = nav.calendarFilter.matchingIds(c.customers);
      final monthEntries = c.entries
          .where((e) =>
              !e.date.isBefore(month) &&
              e.date.isBefore(nextMonth) &&
              (ids == null || ids.contains(e.customerId)))
          .toList();
      final byDay = <int, List<Entry>>{};
      for (final e in monthEntries) {
        byDay.putIfAbsent(e.date.day, () => []).add(e);
      }

      final sold = monthEntries.fold(0.0, (s, e) => s + e.amount);
      final paid = monthEntries.fold(0.0, (s, e) => s + e.paid);
      final qty = monthEntries.fold(0.0, (s, e) => s + e.qty);

      Widget cell(DateTime d) {
        final inMonth = d.month == month.month;
        return _DayCell(
          day: d,
          inMonth: inMonth,
          entries: inMonth ? byDay[d.day] ?? [] : const [],
          onTap: () => nav.openDay(d),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Month selector -----
            Row(children: [
              Text('Monthly', style: t.headlineMedium),
              const SizedBox(width: 24),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () =>
                    nav.month.value = DateTime(month.year, month.month - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 170,
                child: Text(DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center, style: t.titleLarge),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () =>
                    nav.month.value = DateTime(month.year, month.month + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => nav.month.value =
                    DateTime(DateTime.now().year, DateTime.now().month),
                child: const Text('This month'),
              ),
              const Spacer(),
              const SalesCashSwitch(),
            ]),
            const SizedBox(height: 12),
            // ----- Cash book for this month -----
            if (cash) ...[
              CashAddButtons(date: dayToAddOn(month, lastDay)),
              const SizedBox(height: 16),
              Expanded(
                child: CashPeriodView(
                  from: month,
                  to: lastDay,
                  period: 'month',
                  onOpenDay: nav.openDay,
                ),
              ),
            ] else ...[
              CustomerFilterBar(nav.calendarFilter),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                StatCard('Month sales', money(sold)),
                StatCard('Month received', money(paid), color: PayStatus.green.color),
                StatCard('Month balance', money(sold - paid), color: PayStatus.red.color),
                StatCard('Sold', kg(qty)),
              ]),
              const SizedBox(height: 16),

              // ----- Weekday header -----
              Row(children: [
                for (final d in _weekdays)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(d,
                          textAlign: TextAlign.center,
                          style: t.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ),
              ]),

              // ----- Calendar grid -----
              // Rows share the space; if that would make a row shorter than
              // [_minRowHeight] (small window), rows keep that height and scroll.
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final rowHeight = box.maxHeight / weeks < _minRowHeight
                      ? _minRowHeight
                      : box.maxHeight / weeks;
                  return SingleChildScrollView(
                    child: Column(children: [
                      for (var w = 0; w < weeks; w++)
                        SizedBox(
                          height: rowHeight,
                          child: Row(children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                  child: cell(gridStart.add(Duration(days: w * 7 + i)))),
                          ]),
                        ),
                    ]),
                  );
                }),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// One square of the month calendar.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final List<Entry> entries;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.entries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = sameDay(day, DateTime.now());
    final sold = entries.fold(0.0, (s, e) => s + e.amount);
    final paid = entries.fold(0.0, (s, e) => s + e.paid);
    final qty = entries.fold(0.0, (s, e) => s + e.qty);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: !inMonth
            ? Colors.transparent
            : entries.isEmpty
                ? scheme.surfaceContainerLow
                : scheme.primaryContainer.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isToday
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${day.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: !inMonth
                          ? scheme.outline
                          : isToday
                              ? scheme.primary
                              : null,
                    )),
                if (entries.isNotEmpty)
                  Expanded(
                    // Show only the lines that fit, most important first
                    child: LayoutBuilder(builder: (context, box) {
                      final lines = [
                        if (sold > 0) _line(money(sold), FontWeight.w600, null),
                        if (paid > 0)
                          _line(money(paid), FontWeight.w600, PayStatus.green.color),
                        _line(
                            '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}'
                            '${qty > 0 ? ' · ${kg(qty)}' : ''}',
                            FontWeight.normal,
                            scheme.outline),
                      ];
                      final fit = (box.maxHeight / _lineHeight).floor().clamp(0, lines.length);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: lines.take(fit).toList(),
                      );
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _lineHeight = 17.0; // one 12px line of text, with spacing

  Widget _line(String text, FontWeight w, Color? color) => SizedBox(
        height: _lineHeight,
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: w, color: color)),
      );
}
