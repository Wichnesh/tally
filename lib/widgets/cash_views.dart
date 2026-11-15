import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/nav_controller.dart';
import '../controllers/tally_controller.dart';
import '../models.dart';
import '../services/cashbook.dart';
import '../utils.dart';
import 'cash_dialog.dart';
import 'common.dart';
import 'entry_dialog.dart';
import 'history_view.dart';

// Cash book views, used by the Cash book screen and by the
// "Sales | Cash book" switch on Daily, Weekly and Monthly.

final _green = PayStatus.green.color;
final _red = PayStatus.red.color;

/// Works out the cash book for [from]..[to] from all saved data.
List<CashDay> _book(TallyController c, DateTime from, DateTime to) => cashBook(
      accounts: c.accounts,
      movements: movementsFrom(c.entries, c.cashTxns, c.accountForMode),
      txns: c.cashTxns,
      from: from,
      to: to,
    );

/// The day new cash-book lines get on a week or month view: today if it is
/// in the period, otherwise the period's first day. (The form can change it.)
DateTime dayToAddOn(DateTime from, DateTime to) {
  final today = dateOnly(DateTime.now());
  return today.isBefore(dateOnly(from)) || today.isAfter(dateOnly(to)) ? dateOnly(from) : today;
}

/// "Sales | Cash book" switch at the top of Daily, Weekly and Monthly.
/// The choice is shared, so it stays the same when moving between them.
class SalesCashSwitch extends StatelessWidget {
  const SalesCashSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavController>();
    // Words only (no icons), so it fits next to Weekly's Calendar / Table
    // switch in the smallest window.
    return Obx(() => SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sales')),
            ButtonSegment(value: true, label: Text('Cash book')),
          ],
          selected: {nav.calendarCash.value},
          onSelectionChanged: (s) => nav.calendarCash.value = s.first,
        ));
  }
}

/// Add expense / sale entry / money in / transfer / opening balance.
/// New lines are dated [date].
class CashAddButtons extends StatelessWidget {
  final DateTime date;
  const CashAddButtons({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _red),
        onPressed: () => openCashDialog(CashTxn.expense, date: date),
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Add expense'),
      ),
      FilledButton.icon(
        onPressed: () => openEntryDialog(date: date),
        icon: const Icon(Icons.shopping_basket_outlined),
        label: const Text('Add sale entry'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _green),
        onPressed: () => openCashDialog(CashTxn.income, date: date),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Add money in'),
      ),
      OutlinedButton.icon(
        onPressed: () => openCashDialog(CashTxn.transfer, date: date),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Transfer (e.g. cash to bank)'),
      ),
      OutlinedButton.icon(
        onPressed: () => openCashDialog(CashTxn.opening, date: date),
        icon: const Icon(Icons.lock_open),
        label: const Text('Opening balance'),
      ),
    ]);
  }
}

// =====================================================================
// One day
// =====================================================================

/// Cash book for one day: a card per account, then money in, expenses,
/// transfers and opening balances.
class CashDayView extends StatelessWidget {
  final DateTime day;
  const CashDayView(this.day, {super.key});

  @override
  Widget build(BuildContext context) => Obx(() => _build(context)); // redraw on data changes

  Widget _build(BuildContext context) {
    final c = Get.find<TallyController>();
    final cd = _book(c, day, day).first;

    final payments = c.entries.where((e) => sameDay(e.date, day) && e.paid > 0).toList();
    final txns = c.cashTxns.where((x) => sameDay(x.date, day)).toList();
    List<CashTxn> ofType(String type) => txns.where((x) => x.type == type).toList();
    final incomes = ofType(CashTxn.income);
    final expenses = ofType(CashTxn.expense);
    final transfers = ofType(CashTxn.transfer);
    final openings = ofType(CashTxn.opening);

    final moneyIn = payments.fold(0.0, (s, e) => s + e.paid) +
        incomes.fold(0.0, (s, x) => s + x.amount);
    final spent = expenses.fold(0.0, (s, x) => s + x.amount);

    return ListView(children: [
      Wrap(spacing: 16, runSpacing: 16, children: [
        for (final a in cd.accounts.values)
          _AccountCard(
            title: a.account,
            icon: a.account.toLowerCase().contains('cash')
                ? Icons.payments_outlined
                : Icons.account_balance_outlined,
            opening: a.opening,
            moneyIn: a.moneyIn,
            moneyOut: a.moneyOut,
            closing: a.closing,
            difference: a.difference,
            onOpening: () {
              final existing = openings.firstWhereOrNull((x) => x.account == a.account);
              openCashDialog(CashTxn.opening, txn: existing, date: day, account: a.account);
            },
          ),
        _AccountCard(
          title: 'All accounts',
          icon: Icons.summarize_outlined,
          opening: cd.opening,
          moneyIn: cd.moneyIn,
          moneyOut: cd.moneyOut,
          closing: cd.closing,
          highlight: true,
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        'Opening = balance entered when the shop opened, or else the previous day\'s closing. '
        'Money in/out includes transfers between accounts.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 20),

      _Section(
        title: 'Money in',
        total: '+ ${money(moneyIn)}',
        color: _green,
        empty: 'No money came in on this day.',
        children: [
          for (final e in payments)
            ListTile(
              dense: true,
              leading: Icon(Icons.person_outline, color: _green),
              title: Text(c.customerName(e.customerId)),
              subtitle: Text('Customer payment · '
                  '${e.paymentMode.isEmpty ? 'no payment mode' : e.paymentMode} → '
                  '${c.accountForMode(e.paymentMode)}'),
              trailing: Text('+ ${money(e.paid)}',
                  style: TextStyle(color: _green, fontWeight: FontWeight.bold)),
              onTap: () => openEntryDialog(entry: e),
            ),
          for (final x in incomes) _TxnTile(x),
        ],
      ),
      _Section(
        title: 'Expenses',
        total: '− ${money(spent)}',
        color: _red,
        empty: 'No expenses on this day.',
        children: [for (final x in expenses) _TxnTile(x)],
      ),
      if (transfers.isNotEmpty)
        _Section(
          title: 'Transfers between accounts',
          total: money(transfers.fold(0.0, (s, x) => s + x.amount)),
          children: [for (final x in transfers) _TxnTile(x)],
        ),
      if (openings.isNotEmpty)
        _Section(
          title: 'Opening balances entered',
          total: '',
          children: [for (final x in openings) _TxnTile(x)],
        ),
    ]);
  }
}

/// One account's day: opening, in, out, closing.
class _AccountCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double opening, moneyIn, moneyOut, closing;
  final double? difference; // counted - expected
  final VoidCallback? onOpening;
  final bool highlight;

  const _AccountCard({
    required this.title,
    required this.icon,
    required this.opening,
    required this.moneyIn,
    required this.moneyOut,
    required this.closing,
    this.difference,
    this.onOpening,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                    fontSize: bold ? 18 : 14)),
          ]),
        );

    final diff = difference;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (onOpening != null)
              IconButton(
                tooltip: 'Enter the opening balance for this day',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, size: 20),
                onPressed: onOpening,
              ),
          ]),
          const SizedBox(height: 6),
          line(diff == null ? 'Opening' : 'Opening (counted)', money(opening)),
          if (diff != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                diff.abs() < 0.5
                    ? 'Matches the expected balance'
                    : diff < 0
                        ? 'Short by ${money(-diff)}'
                        : 'Extra ${money(diff)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: diff.abs() < 0.5 ? scheme.outline : (diff < 0 ? _red : _green),
                ),
              ),
            ),
          line('+ Money in', money(moneyIn), color: _green),
          line('− Money out', money(moneyOut), color: _red),
          const Divider(height: 14),
          line('Closing', money(closing), bold: true),
        ],
      ),
    );
  }
}

/// A titled group of lines with a total.
class _Section extends StatelessWidget {
  final String title;
  final String total;
  final Color? color;
  final String? empty;
  final List<Widget> children;
  const _Section(
      {required this.title, required this.total, this.color, this.empty, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(total,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ]),
            const SizedBox(height: 4),
            if (children.isEmpty && empty != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(empty!, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One expense / money in / transfer / opening balance, with edit and delete.
class _TxnTile extends StatelessWidget {
  final CashTxn x;
  const _TxnTile(this.x);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TallyController>();
    final (icon, color, title, sign) = switch (x.type) {
      CashTxn.expense => (Icons.remove_circle_outline, _red, x.category, '− '),
      CashTxn.income => (Icons.add_circle_outline, _green, x.category, '+ '),
      CashTxn.transfer => (Icons.swap_horiz, null, '${x.account} → ${x.toAccount}', ''),
      _ => (Icons.lock_open, null, 'Opening balance · ${x.account}', ''),
    };
    final subtitle = [
      if (x.type == CashTxn.expense) 'Paid from ${x.account}',
      if (x.type == CashTxn.income) 'Into ${x.account}',
      if (x.note.isNotEmpty) x.note,
    ].join('  ·  ');

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(title.isEmpty ? x.typeLabel : title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$sign${money(x.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        EditedButton(x.id),
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit, size: 18),
          onPressed: () => openCashDialog(x.type, txn: x),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () async {
            final reason = await askDeleteReason(
                'Delete this ${x.typeLabel.toLowerCase()} of ${money(x.amount)} '
                'on ${shortDate(x.date)}?');
            if (reason != null) c.deleteCashTxn(x.id, reason: reason);
          },
        ),
      ]),
      onTap: () => openCashDialog(x.type, txn: x),
    );
  }
}

// =====================================================================
// A week or a month
// =====================================================================

/// Cash book for a week or a month ([from]..[to]): totals, expenses by type
/// and a day-by-day table. [period] ('week' / 'month') is used in messages.
/// [onOpenDay] runs when a day in the table is clicked.
class CashPeriodView extends StatelessWidget {
  final DateTime from, to;
  final String period;
  final void Function(DateTime day) onOpenDay;
  const CashPeriodView({
    super.key,
    required this.from,
    required this.to,
    required this.period,
    required this.onOpenDay,
  });

  @override
  Widget build(BuildContext context) => Obx(() => _build(context)); // redraw on data changes

  Widget _build(BuildContext context) {
    final c = Get.find<TallyController>();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final today = dateOnly(DateTime.now());
    // Do not list days after today
    final last = to.isAfter(today) ? today : to;
    final days = from.isAfter(today) ? <CashDay>[] : _book(c, from, last);

    final totals = cashTotals(c.entries, c.cashTxns, from, to);
    final spent = totals.spent;
    final net = totals.net;
    final byCategory = totalsByCategory(totals.expenses);
    final accounts = days.isEmpty ? c.accounts.toList() : days.first.accounts.keys.toList();

    return ListView(children: [
      Wrap(spacing: 16, runSpacing: 16, children: [
        StatCard('Customer payments', money(totals.customerIn), color: _green),
        StatCard('Other money in', money(totals.otherIn), color: _green),
        StatCard('Expenses', money(spent), color: _red),
        StatCard('Net (in − expenses)', money(net), color: net < 0 ? _red : _green),
        if (days.isNotEmpty) StatCard('Closing balance', money(days.last.closing)),
      ]),
      const SizedBox(height: 20),

      // ----- Expenses by type -----
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Expenses by type', style: t.titleMedium),
            const SizedBox(height: 12),
            if (byCategory.isEmpty) Text('No expenses this $period.'),
            for (final kv in byCategory) ...[
              Row(children: [
                Expanded(
                    child: Text(kv.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(money(kv.value), style: const TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 52,
                  child: Text('${(kv.value / spent * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right, style: TextStyle(color: scheme.outline)),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: kv.value / spent,
                  minHeight: 8,
                  color: _red,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 20),

      // ----- Day by day -----
      Text('Day by day (click a day to open it)', style: t.titleMedium),
      const SizedBox(height: 8),
      if (days.isEmpty) Text('This $period has not started yet.'),
      if (days.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              const DataColumn(label: Text('Date')),
              const DataColumn(label: Text('Opening'), numeric: true),
              const DataColumn(label: Text('Money in'), numeric: true),
              const DataColumn(label: Text('Money out'), numeric: true),
              const DataColumn(label: Text('Closing'), numeric: true),
              for (final a in accounts) DataColumn(label: Text('$a closing'), numeric: true),
              const DataColumn(label: Text('Counted')),
            ],
            rows: [
              for (final d in days.reversed)
                DataRow(
                  onSelectChanged: (_) => onOpenDay(d.date),
                  cells: [
                    DataCell(Text(DateFormat('EEE, d MMM').format(d.date))),
                    DataCell(Text(money(d.opening))),
                    DataCell(Text(d.moneyIn == 0 ? '-' : '+ ${money(d.moneyIn)}',
                        style: TextStyle(color: _green))),
                    DataCell(Text(d.moneyOut == 0 ? '-' : '− ${money(d.moneyOut)}',
                        style: TextStyle(color: _red))),
                    DataCell(Text(money(d.closing),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    for (final a in accounts) DataCell(Text(money(d.accounts[a]!.closing))),
                    DataCell(_countedText(d)),
                  ],
                ),
            ],
          ),
        ),
    ]);
  }

  /// "Short ₹200" / "Extra ₹100" / "OK" for days with an opening balance entered.
  Widget _countedText(CashDay d) {
    final diffs = d.accounts.values.where((a) => a.difference != null).toList();
    if (diffs.isEmpty) return const Text('-');
    final total = diffs.fold(0.0, (s, a) => s + a.difference!);
    if (total.abs() < 0.5) return const Text('OK');
    return Text(total < 0 ? 'Short ${money(-total)}' : 'Extra ${money(total)}',
        style: TextStyle(color: total < 0 ? _red : _green, fontWeight: FontWeight.w600));
  }
}
