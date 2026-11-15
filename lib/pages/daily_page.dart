import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/nav_controller.dart';
import '../controllers/tally_controller.dart';
import '../utils.dart';
import '../widgets/cash_views.dart';
import '../widgets/common.dart';
import '../widgets/customer_filter_bar.dart';
import '../widgets/entry_dialog.dart';
import '../widgets/history_view.dart';

/// All sales and payments for one day, or (with the "Sales | Cash book"
/// switch) that day's cash book.
class DailyPage extends StatelessWidget {
  const DailyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final nav = Get.find<NavController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      final day = nav.day.value;
      final cash = nav.calendarCash.value;
      // Customer / state / district filter (shared with Weekly and Monthly)
      final ids = nav.calendarFilter.matchingIds(c.customers);
      final list = c
          .entriesOn(day)
          .where((e) => ids == null || ids.contains(e.customerId))
          .toList();
      final qty = list.fold(0.0, (s, e) => s + e.qty);
      final sold = list.fold(0.0, (s, e) => s + e.amount);
      final paid = list.fold(0.0, (s, e) => s + e.paid);

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Date selector -----
            Row(
              children: [
                Text('Daily', style: t.headlineMedium),
                const SizedBox(width: 24),
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () =>
                      nav.day.value = day.subtract(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(longDate(day), style: t.titleMedium),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) nav.day.value = dateOnly(d);
                  },
                ),
                IconButton(
                  tooltip: 'Next day',
                  onPressed: () =>
                      nav.day.value = day.add(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () => nav.day.value = dateOnly(DateTime.now()),
                  child: const Text('Today'),
                ),
                const Spacer(),
                const SalesCashSwitch(),
                if (!cash) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => openEntryDialog(date: day),
                    icon: const Icon(Icons.add),
                    label: const Text('Add entry'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // ----- Cash book for this day -----
            if (cash) ...[
              CashAddButtons(date: day),
              const SizedBox(height: 16),
              Expanded(child: CashDayView(day)),
            ] else ...[
              CustomerFilterBar(nav.calendarFilter),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  StatCard('Quantity sold', kg(qty)),
                  StatCard('Sales', money(sold)),
                  StatCard('Received', money(paid), color: PayStatus.green.color),
                ],
              ),
              const SizedBox(height: 16),

              // ----- Entries table -----
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          ids == null
                              ? 'No entries on this day. Press "Add entry".'
                              : 'No entries on this day for the chosen customers.',
                        ),
                      )
                    // Scrolls down for many entries, and sideways if the table is
                    // wider than the window (fills the width when it fits).
                    : LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: box.maxWidth),
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Customer')),
                                  DataColumn(label: Text('Product')),
                                  DataColumn(label: Text('Qty'), numeric: true),
                                  DataColumn(
                                    label: Text('Price/kg'),
                                    numeric: true,
                                  ),
                                  DataColumn(label: Text('Sale'), numeric: true),
                                  DataColumn(label: Text('Paid'), numeric: true),
                                  DataColumn(label: Text('Note')),
                                  DataColumn(label: Text('')),
                                ],
                                rows: [
                                  for (final e in list)
                                    DataRow(
                                      cells: [
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 6,
                                                backgroundColor: c
                                                    .statusOf(e.customerId)
                                                    .color,
                                              ),
                                              const SizedBox(width: 8),
                                              // Long names are shortened with "…"; hover shows all
                                              ConstrainedBox(
                                                constraints: const BoxConstraints(
                                                  maxWidth: 280,
                                                ),
                                                child: Tooltip(
                                                  message: c.customerName(
                                                    e.customerId,
                                                  ),
                                                  child: Text(
                                                    c.customerName(e.customerId),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            e.product.isEmpty ? '-' : e.product,
                                          ),
                                        ),
                                        DataCell(
                                          Text(e.qty == 0 ? '-' : kg(e.qty)),
                                        ),
                                        DataCell(
                                          Text(e.qty == 0 ? '-' : perKg(e.rate)),
                                        ),
                                        DataCell(
                                          Text(
                                            e.qty == 0 ? '-' : money(e.amount),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            paidText(e.paid, e.paymentMode),
                                            style: TextStyle(
                                              color: PayStatus.green.color,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(e.note)),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              EditedButton(e.id),
                                              IconButton(
                                                tooltip: 'Edit',
                                                icon: const Icon(
                                                  Icons.edit,
                                                  size: 18,
                                                ),
                                                onPressed: () =>
                                                    openEntryDialog(entry: e),
                                              ),
                                              IconButton(
                                                tooltip: 'Delete',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                ),
                                                onPressed: () async {
                                                  final reason =
                                                      await askDeleteReason(
                                                        'Delete this entry of ${c.customerName(e.customerId)}?',
                                                      );
                                                  if (reason != null) {
                                                    c.deleteEntry(
                                                      e.id,
                                                      reason: reason,
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ],
        ),
      );
    });
  }
}
