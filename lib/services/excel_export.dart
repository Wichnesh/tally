import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/tally_controller.dart';
import '../models.dart';
import 'cashbook.dart';

/// Builds an Excel (.xlsx) file for the dates [from]..[to] (inclusive).
/// Pass null for both to export everything.
/// [customerFilter] limits the file to customers it accepts (null = everyone),
/// e.g. the Customer / State / District filter's `matches`.
///
/// Sheets:
///  1. Customers – totals per customer for the period + all-time balance
///  2. Entries   – every sale / payment line
///  3. Products  – kg and amount sold per product
///  4. Daily     – totals per day
///  5. Change history – every edit / deletion with old and new values and reason
///  6. Cash book – each day, each account: opening, money in, money out, closing
///  7. Expenses & money in – every expense, other money in, transfer, opening balance
/// Sheets 6 and 7 are shop-wide, so they are left out when [customerFilter] is set.
Uint8List buildExcel(
    {DateTime? from, DateTime? to, bool Function(Customer)? customerFilter}) {
  final c = Get.find<TallyController>();
  final customerIds = customerFilter == null
      ? null
      : {for (final cu in c.customers.where(customerFilter)) cu.id};
  bool chosen(String customerId) => customerIds == null || customerIds.contains(customerId);

  // Deleted customers are no longer in the list. For the Change history sheet,
  // their state and district are taken from the record of their deletion,
  // so a "Tamil Nadu" export still includes a deleted Tamil Nadu customer.
  final deletedPlace = <String, Customer>{};
  for (final h in c.history) {
    if (h.kind != 'customer' || h.action != 'deleted') continue;
    String was(String field) {
      final v = h.changes.firstWhereOrNull((ch) => ch.field == field)?.from ?? '';
      return v == '-' ? '' : v;
    }
    deletedPlace[h.customerId] = Customer(
        id: h.customerId, name: '', state: was('State'), district: was('District'));
  }
  bool historyChosen(HistoryItem h) {
    if (customerFilter == null) return true;
    final cu = c.customerById(h.customerId) ?? deletedPlace[h.customerId];
    return cu != null && customerFilter(cu);
  }
  bool inRange(Entry e) =>
      (from == null || !e.date.isBefore(from)) &&
      (to == null || !e.date.isAfter(to)) &&
      chosen(e.customerId);
  final list = c.entries.where(inRange).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final excel = Excel.createExcel();
  final header = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('#FFE8A6'),
  );
  final bold = CellStyle(bold: true);

  Sheet sheet(String name, List<String> titles, List<double> widths) {
    final s = excel[name];
    s.appendRow(titles.map((t) => TextCellValue(t)).toList());
    for (final cell in s.row(0)) {
      cell?.cellStyle = header;
    }
    for (var i = 0; i < widths.length; i++) {
      s.setColumnWidth(i, widths[i]);
    }
    return s;
  }

  CellValue txt(String v) => TextCellValue(v);
  CellValue num(double v) => DoubleCellValue(double.parse(v.toStringAsFixed(2)));
  CellValue date(DateTime d) => DateCellValue(year: d.year, month: d.month, day: d.day);

  void totalRow(Sheet s, List<CellValue?> row) {
    s.appendRow(row);
    for (final cell in s.row(s.maxRows - 1)) {
      cell?.cellStyle = bold;
    }
  }

  // ----- 1. Customers -----
  final cs = sheet('Customers', [
    'Code', 'Customer', 'Phone', 'Area / Town', 'District', 'State', 'Bought (₹)',
    'Paid (₹)', 'Balance (₹)', 'Paid %', 'All-time balance (₹)', 'Status',
    'Old book: purchases (₹)', 'Old book: paid (₹)', 'Old book: as on',
  ], [10, 26, 16, 20, 16, 18, 14, 14, 14, 10, 20, 12, 22, 20, 16]);
  double tSold = 0, tPaid = 0;
  for (final cu in c.customers.where((x) => chosen(x.id))) {
    final mine = list.where((e) => e.customerId == cu.id);
    final sold = mine.fold(0.0, (s, e) => s + e.amount);
    final paid = mine.fold(0.0, (s, e) => s + e.paid);
    tSold += sold;
    tPaid += paid;
    final pct = c.percent(sold, paid);
    cs.appendRow([
      txt(cu.code),
      txt(cu.name),
      txt(cu.phone),
      txt(cu.location),
      txt(cu.district),
      txt(cu.state),
      num(sold),
      num(paid),
      num(sold - paid),
      pct == null ? txt('-') : num(pct),
      num(c.balanceOf(cu.id)),
      txt(c.statusOf(cu.id).name.toUpperCase()),
      cu.hasOpening ? num(cu.openingBought) : null,
      cu.hasOpening ? num(cu.openingPaid) : null,
      cu.openingDate == null ? null : date(cu.openingDate!),
    ]);
  }
  totalRow(cs, [
    txt('TOTAL'), null, null, null, null, null, num(tSold), num(tPaid), num(tSold - tPaid),
    c.percent(tSold, tPaid) == null ? null : num(c.percent(tSold, tPaid)!),
  ]);

  // ----- 2. Entries -----
  final es = sheet('Entries', [
    'Date', 'Code', 'Customer', 'District', 'State', 'Product', 'Qty (kg)',
    'Percent (%)', 'Rate (₹)', 'Price/kg (₹)', 'Sale (₹)', 'Paid (₹)', 'Payment mode', 'Note',
  ], [14, 10, 26, 16, 18, 20, 10, 11, 12, 13, 14, 14, 16, 30]);
  for (final e in list) {
    es.appendRow([
      date(e.date),
      txt(c.customerById(e.customerId)?.code ?? ''),
      txt(c.customerById(e.customerId)?.name ?? 'Deleted customer'),
      txt(c.customerById(e.customerId)?.district ?? ''),
      txt(c.customerById(e.customerId)?.state ?? ''),
      txt(e.product),
      num(e.qty),
      e.percent == null ? null : num(e.percent!),
      e.baseRate == null ? null : num(e.baseRate!),
      num(e.rate),
      num(e.amount),
      num(e.paid),
      txt(e.paymentMode),
      txt(e.note),
    ]);
  }
  totalRow(es, [
    txt('TOTAL'), null, null, null, null, null,
    num(list.fold(0.0, (s, e) => s + e.qty)), null, null, null,
    num(tSold), num(tPaid),
  ]);

  // ----- 3. Products -----
  final ps = sheet('Products', ['Product', 'Qty (kg)', 'Sales (₹)', 'Avg price/kg (₹)'],
      [24, 12, 16, 16]);
  final byProduct = <String, List<Entry>>{};
  for (final e in list.where((e) => e.qty > 0)) {
    byProduct.putIfAbsent(e.product.isEmpty ? '(none)' : e.product, () => []).add(e);
  }
  for (final kv in byProduct.entries) {
    final qty = kv.value.fold(0.0, (s, e) => s + e.qty);
    final amt = kv.value.fold(0.0, (s, e) => s + e.amount);
    ps.appendRow([txt(kv.key), num(qty), num(amt), num(qty == 0 ? 0 : amt / qty)]);
  }

  // ----- 4. Daily -----
  final ds = sheet('Daily', ['Date', 'Entries', 'Qty (kg)', 'Sales (₹)', 'Received (₹)'],
      [14, 10, 12, 16, 16]);
  final byDay = <DateTime, List<Entry>>{};
  for (final e in list) {
    byDay.putIfAbsent(e.date, () => []).add(e);
  }
  for (final kv in byDay.entries) {
    ds.appendRow([
      date(kv.key),
      IntCellValue(kv.value.length),
      num(kv.value.fold(0.0, (s, e) => s + e.qty)),
      num(kv.value.fold(0.0, (s, e) => s + e.amount)),
      num(kv.value.fold(0.0, (s, e) => s + e.paid)),
    ]);
  }

  // ----- 5. Change history -----
  final hs = sheet('Change history',
      ['When', 'Action', 'Customer', 'What', 'Field', 'Old value', 'New value', 'Reason'],
      [20, 10, 28, 22, 14, 24, 24, 40]);
  final whenFmt = DateFormat('d MMM yyyy, h:mm a');
  for (final h in c.history.reversed) {
    if (!historyChosen(h)) continue;
    final day = DateTime(h.at.year, h.at.month, h.at.day);
    if ((from != null && day.isBefore(from)) || (to != null && day.isAfter(to))) continue;
    // One row per changed field, so it is easy to filter in Excel
    for (final ch in h.changes.isEmpty ? [Change('', '', '')] : h.changes) {
      hs.appendRow([
        txt(whenFmt.format(h.at)),
        txt(h.action),
        txt(h.customerLabel),
        txt(h.what),
        txt(ch.field),
        txt(ch.from),
        txt(ch.to),
        txt(h.reason),
      ]);
    }
  }

  if (customerFilter == null) _cashSheets(c, sheet, txt, num, date, from, to);

  excel.setDefaultSheet('Customers');
  excel.delete('Sheet1');
  return Uint8List.fromList(excel.encode()!);
}

/// Sheets 6 and 7: the Cash book.
void _cashSheets(
  TallyController c,
  Sheet Function(String, List<String>, List<double>) sheet,
  CellValue Function(String) txt,
  CellValue Function(double) num,
  CellValue Function(DateTime) date,
  DateTime? from,
  DateTime? to,
) {
  final inRange = c.cashTxns
      .where((x) =>
          (from == null || !x.date.isBefore(from)) && (to == null || !x.date.isAfter(to)))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // ----- 6. Cash book (one row per day per account) -----
  final moves = movementsFrom(c.entries, c.cashTxns, c.accountForMode);
  final allDates = [...moves.map((m) => m.date), ...c.cashTxns.map((x) => x.date)];
  final today = DateTime.now();
  final start = from ?? (allDates.isEmpty ? null : allDates.reduce((a, b) => a.isBefore(b) ? a : b));
  var end = to ?? DateTime(today.year, today.month, today.day);
  if (end.isAfter(today)) end = DateTime(today.year, today.month, today.day);
  final cb = sheet('Cash book', [
    'Date', 'Account', 'Opening (₹)', 'Counted?', 'Short (-) / Extra (+) (₹)',
    'Money in (₹)', 'Money out (₹)', 'Closing (₹)',
  ], [14, 20, 14, 10, 20, 14, 14, 14]);
  if (start != null && !start.isAfter(end)) {
    for (final day in cashBook(
        accounts: c.accounts, movements: moves, txns: c.cashTxns, from: start, to: end)) {
      for (final a in day.accounts.values) {
        cb.appendRow([
          date(day.date),
          txt(a.account),
          num(a.opening),
          txt(a.counted == null ? '' : 'Yes'),
          a.difference == null ? null : num(a.difference!),
          num(a.moneyIn),
          num(a.moneyOut),
          num(a.closing),
        ]);
      }
    }
  }

  // ----- 7. Expenses & money in -----
  final xs = sheet('Expenses & money in', [
    'Date', 'Type', 'Expense type / source', 'Account', 'To account', 'Amount (₹)', 'Note',
  ], [14, 16, 24, 18, 18, 14, 30]);
  for (final x in inRange) {
    xs.appendRow([
      date(x.date),
      txt(x.typeLabel),
      txt(x.category),
      txt(x.account),
      txt(x.toAccount),
      num(x.amount),
      txt(x.note),
    ]);
  }
  for (final type in [CashTxn.expense, CashTxn.income]) {
    final total = inRange.where((x) => x.type == type).fold(0.0, (s, x) => s + x.amount);
    xs.appendRow([
      txt(type == CashTxn.expense ? 'TOTAL EXPENSES' : 'TOTAL MONEY IN'),
      null, null, null, null, num(total),
    ]);
  }
}
