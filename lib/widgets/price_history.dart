import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../models.dart';
import '../utils.dart';

/// Price history of one customer, built from their daily entries.
/// Shows the current price of each product, then every day's price
/// with the change from the previous price of that product.
class PriceHistory extends StatefulWidget {
  final String customerId;
  const PriceHistory({super.key, required this.customerId});

  @override
  State<PriceHistory> createState() => _PriceHistoryState();
}

class _PriceHistoryState extends State<PriceHistory> {
  bool _onlyChanges = false;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      // Sales only, oldest first
      final sales = c.entriesOf(widget.customerId).where((e) => e.qty > 0).toList();
      if (sales.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No sales yet, so no prices to show.')),
        );
      }

      // Walk through sales and compare each price with the previous
      // price of the same product.
      final lastPrice = <String, double>{};
      final since = <String, DateTime>{}; // when the current price started
      final rows = <({Entry e, double? change})>[];
      for (final e in sales) {
        final prev = lastPrice[e.product];
        final change = prev == null ? null : e.rate - prev;
        if (prev == null || change != 0) since[e.product] = e.date;
        lastPrice[e.product] = e.rate;
        rows.add((e: e, change: change));
      }

      final shown = rows.reversed
          .where((r) => !_onlyChanges || r.change == null || r.change != 0)
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current price', style: t.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final product in lastPrice.keys)
              Chip(
                label: Text(
                    '${product.isEmpty ? 'No product' : product}: ${perKg(lastPrice[product]!)}/kg'
                    '  ·  since ${shortDate(since[product]!)}'),
              ),
          ]),
          const SizedBox(height: 12),
          FilterChip(
            label: const Text('Show only price changes'),
            selected: _onlyChanges,
            onSelected: (v) => setState(() => _onlyChanges = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Percent'), numeric: true),
                DataColumn(label: Text('Rate'), numeric: true),
                DataColumn(label: Text('Price/kg'), numeric: true),
                DataColumn(label: Text('Change')),
              ],
              rows: [
                for (final r in shown)
                  DataRow(cells: [
                    DataCell(Text(longDate(r.e.date))),
                    DataCell(Text(r.e.product.isEmpty ? '-' : r.e.product)),
                    DataCell(Text(kg(r.e.qty))),
                    DataCell(Text(r.e.percent == null ? '-' : pctText(r.e.percent!))),
                    DataCell(Text(r.e.baseRate == null ? '-' : money(r.e.baseRate!))),
                    DataCell(Text(perKg(r.e.rate),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(_changeText(r.change)),
                  ]),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _changeText(double? change) {
    if (change == null) return const Text('First price');
    if (change == 0) return const Text('Same', style: TextStyle(color: Colors.grey));
    final up = change > 0;
    return Text(
      '${up ? '▲' : '▼'} ${perKg((change.abs() * 100).roundToDouble() / 100)}',
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: up ? PayStatus.red.color : PayStatus.green.color,
      ),
    );
  }
}
