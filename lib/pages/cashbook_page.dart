import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/nav_controller.dart';
import '../utils.dart';
import '../widgets/cash_views.dart';

/// Cash book: money in each account (Cash, Bank…) day by day.
///   Opening (counted, or yesterday's closing) + money in − money out = Closing
/// Money in  = customer payments (by payment mode) + other money in.
/// Money out = shop expenses. Transfers move money between accounts.
/// The views are in widgets/cash_views.dart (also used by Daily, Weekly, Monthly).
class CashBookPage extends StatelessWidget {
  const CashBookPage({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      final monthView = nav.cashMonthView.value;
      final day = nav.cashDay.value;
      final month = nav.cashMonth.value;

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Title, Day / Month, date -----
            Row(children: [
              Text('Cash book', style: t.headlineMedium),
              const SizedBox(width: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.today), label: Text('Day')),
                  ButtonSegment(
                      value: true, icon: Icon(Icons.calendar_month), label: Text('Month')),
                ],
                selected: {monthView},
                onSelectionChanged: (s) => nav.cashMonthView.value = s.first,
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: monthView ? 'Previous month' : 'Previous day',
                onPressed: () => monthView
                    ? nav.cashMonth.value = DateTime(month.year, month.month - 1)
                    : nav.cashDay.value = DateTime(day.year, day.month, day.day - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              if (monthView)
                SizedBox(
                  width: 150,
                  child: Text(DateFormat('MMMM yyyy').format(month),
                      textAlign: TextAlign.center, style: t.titleMedium),
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(longDate(day), style: t.titleMedium),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null) nav.cashDay.value = dateOnly(d);
                  },
                ),
              IconButton(
                tooltip: monthView ? 'Next month' : 'Next day',
                onPressed: () => monthView
                    ? nav.cashMonth.value = DateTime(month.year, month.month + 1)
                    : nav.cashDay.value = DateTime(day.year, day.month, day.day + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  nav.cashDay.value = dateOnly(now);
                  nav.cashMonth.value = DateTime(now.year, now.month);
                },
                child: Text(monthView ? 'This month' : 'Today'),
              ),
            ]),
            const SizedBox(height: 12),
            CashAddButtons(date: day),
            const SizedBox(height: 16),
            Expanded(
              child: monthView
                  ? CashPeriodView(
                      from: month,
                      to: DateTime(month.year, month.month + 1, 0),
                      period: 'month',
                      onOpenDay: nav.openCashDay,
                    )
                  : CashDayView(day),
            ),
          ],
        ),
      );
    });
  }
}
