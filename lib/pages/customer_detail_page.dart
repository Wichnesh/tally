import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/customer_dialog.dart';
import '../widgets/entry_dialog.dart';
import '../widgets/history_view.dart';
import '../widgets/price_history.dart';
import '../widgets/proof_tile.dart';

/// One customer's full ledger with running balance.
class CustomerDetailPage extends StatelessWidget {
  final String customerId;
  CustomerDetailPage({super.key, required this.customerId});

  final _view = 0.obs; // 0 = Entries, 1 = Price history, 2 = Change history

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();

    return Obx(() {
      final cu = c.customerById(customerId);
      if (cu == null) return const Scaffold(); // just deleted

      final sold = c.soldOf(customerId);
      final paid = c.paidOf(customerId);
      final pct = c.percent(sold, paid);
      final status = c.statusFor(pct);

      // Running balance, oldest -> newest, then show newest first
      final list = c.entriesOf(customerId);
      final balances = <String, double>{};
      double running = cu.openingBalance; // starts from the old book
      for (final e in list) {
        running += e.amount - e.paid;
        balances[e.id] = running;
      }
      final rows = list.reversed.toList();

      return Scaffold(
        appBar: AppBar(
          title: Row(children: [
            CircleAvatar(radius: 8, backgroundColor: status.color),
            const SizedBox(width: 10),
            Text(cu.name),
            const SizedBox(width: 10),
            CodeChip(cu.code),
            if (cu.phone.isNotEmpty)
              Text('   ${cu.phone}', style: Theme.of(context).textTheme.bodyMedium),
          ]),
          actions: [
            TextButton.icon(
              onPressed: () => openCustomerDialog(cu),
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
            ),
            TextButton.icon(
              onPressed: () async {
                final reason = await askDeleteReason(
                    'Delete ${cu.label} and all ${list.length} entries? '
                    'This cannot be undone.');
                if (reason != null) {
                  Get.back();
                  c.deleteCustomer(customerId, reason: reason);
                }
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(width: 12),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openEntryDialog(customerId: customerId),
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
          children: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              StatCard('Total bought', money(sold)),
              StatCard('Total paid', money(paid), color: PayStatus.green.color),
              StatCard('Balance due', money(sold - paid), color: PayStatus.red.color),
              StatCard('Paid %', pct == null ? '-' : '${pct.toStringAsFixed(1)}%',
                  color: status.color),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(pct),
                if (cu.place.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on, size: 16),
                    const SizedBox(width: 4),
                    Text(cu.place),
                  ]),
              ],
            ),
            if (cu.proofs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Proofs', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final path in cu.proofs) ProofTile(path),
              ]),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0, icon: Icon(Icons.receipt_long), label: Text('Entries')),
                  ButtonSegment(
                      value: 1, icon: Icon(Icons.trending_up), label: Text('Price history')),
                  ButtonSegment(
                      value: 2, icon: Icon(Icons.history), label: Text('Change history')),
                ],
                selected: {_view.value},
                onSelectionChanged: (s) => _view.value = s.first,
              ),
            ),
            const SizedBox(height: 12),
            if (_view.value == 1)
              PriceHistory(customerId: customerId)
            else if (_view.value == 2)
              HistoryList(c.historyOfCustomer(customerId),
                  showCustomer: false,
                  emptyText: 'No edits or deletions for this customer yet.')
            else if (rows.isEmpty && !cu.hasOpening)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No entries yet for this customer.')),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Qty'), numeric: true),
                    DataColumn(label: Text('Price/kg'), numeric: true),
                    DataColumn(label: Text('Sale'), numeric: true),
                    DataColumn(label: Text('Paid'), numeric: true),
                    DataColumn(label: Text('Balance'), numeric: true),
                    DataColumn(label: Text('Note')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final e in rows)
                      DataRow(cells: [
                        DataCell(Text(longDate(e.date))),
                        DataCell(Text(e.product.isEmpty ? '-' : e.product)),
                        DataCell(Text(e.qty == 0 ? '-' : kg(e.qty))),
                        DataCell(Tooltip(
                            message: formulaText(e.percent, e.baseRate).isEmpty
                                ? 'Price typed directly'
                                : '${formulaText(e.percent, e.baseRate)} ÷ divisor',
                            child: Text(e.qty == 0 ? '-' : perKg(e.rate)))),
                        DataCell(Text(e.qty == 0 ? '-' : money(e.amount))),
                        DataCell(Text(paidText(e.paid, e.paymentMode),
                            style: TextStyle(color: PayStatus.green.color))),
                        DataCell(Text(money(balances[e.id]!),
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(e.note)),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          EditedButton(e.id),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => openEntryDialog(entry: e),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final reason = await askDeleteReason(
                                  'Delete the entry of ${shortDate(e.date)}?');
                              if (reason != null) c.deleteEntry(e.id, reason: reason);
                            },
                          ),
                        ])),
                      ]),
                    // Figures brought in from the old book (always the first line)
                    if (cu.hasOpening)
                      DataRow(
                        color: WidgetStatePropertyAll(Colors.amber.withValues(alpha: 0.08)),
                        cells: [
                          DataCell(Text(cu.openingDate == null
                              ? 'Opening'
                              : longDate(cu.openingDate!))),
                          const DataCell(Text('Opening (old book)',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                          const DataCell(Text('-')),
                          const DataCell(Text('-')),
                          DataCell(Text(money(cu.openingBought))),
                          DataCell(Text(cu.openingPaid == 0 ? '-' : money(cu.openingPaid),
                              style: TextStyle(color: PayStatus.green.color))),
                          DataCell(Text(money(cu.openingBalance),
                              style: const TextStyle(fontWeight: FontWeight.bold))),
                          const DataCell(Text('Brought forward')),
                          DataCell(IconButton(
                            tooltip: 'Change in Edit customer',
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => openCustomerDialog(cu),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}
