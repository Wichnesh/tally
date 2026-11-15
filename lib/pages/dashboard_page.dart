import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/dashboard_controller.dart';
import '../controllers/nav_controller.dart';
import '../controllers/tally_controller.dart';
import '../models.dart';
import '../services/backup_service.dart';
import '../services/stats.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/customer_filter_bar.dart';
import '../widgets/entry_dialog.dart';

/// Dashboard:
///  1. Filters (period, customer)
///  2. Totals for the chosen period
///  3. Sales by product and Payments by mode (each with its own filter chips)
///  4. All-time totals and customers from worst payer to best
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final f = Get.find<DashboardController>();
    final t = Theme.of(context).textTheme;

    return Obx(() {
      // ----- Period figures -----
      final (from, to) = f.range;
      // Customers chosen by the customer / state / district filter (null = all)
      final ids = f.customers.matchingIds(c.customers);
      final periodEntries =
          entriesInRange(c.entries, from: from, to: to, customerIds: ids);

      final allProducts = productStats(periodEntries);
      final allModes = modeStats(periodEntries);
      final shownProducts = productStats(periodEntries, only: f.products);
      final shownModes = modeStats(periodEntries, only: f.modes);

      final pSales = shownProducts.fold(0.0, (s, x) => s + x.amount);
      final pQty = shownProducts.fold(0.0, (s, x) => s + x.qty);
      final pReceived = shownModes.fold(0.0, (s, x) => s + x.amount);
      final periodSold = periodEntries.fold(0.0, (s, e) => s + e.amount);
      final periodPaid = periodEntries.fold(0.0, (s, e) => s + e.paid);

      // Shop expenses in the period (Cash book). Not linked to customers,
      // so only shown when no customer / state / district filter is on.
      final showExpenses = ids == null;
      final periodExpenses = c.cashTxns
          .where((x) =>
              x.type == CashTxn.expense &&
              (from == null || !x.date.isBefore(from)) &&
              (to == null || !x.date.isAfter(to)))
          .fold(0.0, (s, x) => s + x.amount);

      // Chip choices: every product / mode in the lists, plus any used in entries
      final productChoices = {...c.products, ...allProducts.map((x) => x.product)}.toList();
      final modeChoices = {...c.paymentModes, ...allModes.map((x) => x.mode)}.toList();

      // ----- All-time figures (customer filter applies, period does not) -----
      final allTimeEntries = entriesInRange(c.entries, customerIds: ids);
      final shownCustomers =
          ids == null ? c.customers.toList() : c.customers.where((x) => ids.contains(x.id)).toList();
      // Includes the figures brought in from the old book
      final sold = shownCustomers.fold(0.0, (s, x) => s + x.openingBought) +
          allTimeEntries.fold(0.0, (s, e) => s + e.amount);
      final paid = shownCustomers.fold(0.0, (s, x) => s + x.openingPaid) +
          allTimeEntries.fold(0.0, (s, e) => s + e.paid);
      final pct = c.percent(sold, paid);
      final counts = {for (final s in PayStatus.values) s: 0};
      for (final cu in shownCustomers) {
        counts[c.statusOf(cu.id)] = counts[c.statusOf(cu.id)]! + 1;
      }
      final sorted = shownCustomers
        ..sort((a, b) => (c.percentOf(a.id) ?? 1e9).compareTo(c.percentOf(b.id) ?? 1e9));
      final who = f.customers.describe(c.customerName);

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Text('Dashboard', style: t.headlineMedium),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => openEntryDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            ),
          ]),
          if (!Get.find<BackupService>().hasPassword.value) ...[
            const SizedBox(height: 16),
            Material(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('Backups are off'),
                subtitle: const Text('Set a backup password to protect your data.'),
                trailing: TextButton(
                  onPressed: () => Get.find<NavController>().tab.value = Tabs.backup,
                  child: const Text('Turn on'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ===== 1. Filters =====
          const _FilterBar(),
          const SizedBox(height: 16),

          // ===== 2. Period totals =====
          Wrap(spacing: 16, runSpacing: 16, children: [
            StatCard(f.products.isEmpty ? 'Sales' : 'Sales (selected products)',
                money(pSales)),
            StatCard(f.products.isEmpty ? 'Quantity sold' : 'Quantity sold (selected)',
                kg(pQty)),
            StatCard(f.modes.isEmpty ? 'Received' : 'Received (selected modes)',
                money(pReceived),
                color: PayStatus.green.color),
            StatCard('Balance for period', money(periodSold - periodPaid),
                color: PayStatus.red.color),
            StatCard('Entries', '${periodEntries.length}'),
            if (showExpenses) ...[
              StatCard('Expenses', money(periodExpenses), color: PayStatus.red.color),
              StatCard('Net (received − expenses)', money(periodPaid - periodExpenses),
                  color: periodPaid - periodExpenses < 0
                      ? PayStatus.red.color
                      : PayStatus.green.color),
            ],
          ]),
          const SizedBox(height: 16),

          // ===== 3. Breakdown by product and by payment mode =====
          LayoutBuilder(builder: (context, box) {
            final products = _BreakdownCard(
              icon: Icons.inventory_2_outlined,
              title: 'Sales by product',
              empty: 'No sales in this period.',
              choices: productChoices,
              selected: f.products,
              onToggle: (v) => f.toggle(f.products, v),
              onAll: f.products.clear,
              total: pSales,
              totalLine: '${kg(pQty)}  ·  ${money(pSales)}',
              barColor: Theme.of(context).colorScheme.primary,
              rows: [
                for (final p in shownProducts)
                  _Row(
                    name: p.product,
                    value: p.amount,
                    detail: '${kg(p.qty)}  ·  avg ${money(p.avgRate)}/kg  ·  '
                        '${p.count} ${p.count == 1 ? 'sale' : 'sales'}',
                  ),
              ],
            );
            final modes = _BreakdownCard(
              icon: Icons.payments_outlined,
              title: 'Payments by mode',
              empty: 'No payments in this period.',
              choices: modeChoices,
              selected: f.modes,
              onToggle: (v) => f.toggle(f.modes, v),
              onAll: f.modes.clear,
              total: pReceived,
              totalLine: money(pReceived),
              barColor: PayStatus.green.color,
              rows: [
                for (final m in shownModes)
                  _Row(
                    name: m.mode,
                    value: m.amount,
                    detail: '${m.count} ${m.count == 1 ? 'payment' : 'payments'}',
                  ),
              ],
            );
            if (box.maxWidth < 1000) {
              return Column(children: [products, const SizedBox(height: 16), modes]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: products),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: modes),
            ]);
          }),
          const SizedBox(height: 32),

          // ===== 4. All time =====
          Text(who.isEmpty ? 'All time' : 'All time  ·  $who', style: t.titleLarge),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 16, children: [
            StatCard('Total sales', money(sold)),
            StatCard('Total received', money(paid), color: PayStatus.green.color),
            StatCard('Outstanding', money(sold - paid), color: PayStatus.red.color),
            StatCard('Collected', pct == null ? '-' : '${pct.toStringAsFixed(1)}%',
                color: c.statusFor(pct).color),
          ]),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final s in [PayStatus.red, PayStatus.yellow, PayStatus.green])
              Chip(
                avatar: CircleAvatar(backgroundColor: s.color, radius: 8),
                label: Text('${s.label}: ${counts[s]}'),
              ),
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text(
                  'Red below ${c.redBelow.value.toInt()}%  ·  Green from ${c.greenFrom.value.toInt()}%'),
              onPressed: () => Get.find<NavController>().tab.value = Tabs.settings,
            ),
          ]),
          const SizedBox(height: 24),
          Text('Customers (lowest payment first)', style: t.titleMedium),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(c.customers.isEmpty
                      ? 'No customers yet. Go to Customers to add your first one.'
                      : 'No customers match the filter.')),
            ),
          for (final cu in sorted) CustomerTile(cu.id),
        ],
      );
    });
  }
}

// =====================================================================
// Filter bar: period + customer
// =====================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  Future<void> _pickDates(BuildContext context, DashboardController f) async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: f.customFrom.value == null
          ? null
          : DateTimeRange(start: f.customFrom.value!, end: f.customTo.value!),
    );
    if (r != null) {
      f.customFrom.value = r.start;
      f.customTo.value = r.end;
      f.period.value = Period.custom;
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Get.find<DashboardController>();
    final c = Get.find<TallyController>();
    final scheme = Theme.of(context).colorScheme;

    return Obx(() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 20),
                  for (final p in Period.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: f.period.value == p,
                      onSelected: (_) => p == Period.custom
                          ? _pickDates(context, f)
                          : f.period.value = p,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CustomerFilterBar(f.customers, showClear: false),
                  if (f.isFiltered)
                    TextButton.icon(
                      onPressed: f.reset,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset filters'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                  'Showing: ${f.rangeText}'
                  '${f.customers.isActive ? '  ·  ${f.customers.describe(c.customerName)}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ));
  }
}

// =====================================================================
// Breakdown card: chips to choose items + one bar per item
// =====================================================================

class _Row {
  final String name;
  final double value;
  final String detail;
  _Row({required this.name, required this.value, required this.detail});
}

class _BreakdownCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String empty;
  final List<String> choices;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onAll;
  final List<_Row> rows;
  final double total;
  final String totalLine;
  final Color barColor;

  const _BreakdownCard({
    required this.icon,
    required this.title,
    required this.empty,
    required this.choices,
    required this.selected,
    required this.onToggle,
    required this.onAll,
    required this.rows,
    required this.total,
    required this.totalLine,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: t.titleMedium),
            ]),
            const SizedBox(height: 10),

            // Which items to include
            Wrap(spacing: 6, runSpacing: 6, children: [
              FilterChip(
                label: const Text('All'),
                selected: selected.isEmpty,
                onSelected: (_) => onAll(),
              ),
              for (final ch in choices)
                FilterChip(
                  label: Text(ch),
                  selected: selected.contains(ch),
                  onSelected: (_) => onToggle(ch),
                ),
            ]),
            const SizedBox(height: 14),

            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(empty)),
              ),
            for (final r in rows) ...[
              Row(children: [
                Expanded(
                  child: Text(r.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(money(r.value),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()])),
                SizedBox(
                  width: 52,
                  child: Text(
                    total == 0 ? '' : '${(r.value / total * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: scheme.outline),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : r.value / total,
                  minHeight: 8,
                  color: barColor,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 3),
              Text(r.detail, style: TextStyle(fontSize: 12, color: scheme.outline)),
              const SizedBox(height: 12),
            ],
            if (rows.length > 1) ...[
              const Divider(),
              Row(children: [
                const Expanded(
                    child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                Text(totalLine, style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
