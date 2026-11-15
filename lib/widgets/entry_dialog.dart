import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../models.dart';
import '../utils.dart';
import 'customer_filter_bar.dart';
import 'history_view.dart';

/// Opens the "sale / payment" form.
/// Pass [entry] to edit, or [customerId] / [date] to pre-fill a new one.
Future<void> openEntryDialog({Entry? entry, String? customerId, DateTime? date}) {
  if (entry == null && Get.find<TallyController>().customers.isEmpty) {
    Get.snackbar('No customers yet', 'Add a customer first in the Customers screen.',
        snackPosition: SnackPosition.BOTTOM, maxWidth: 500);
    return Future.value();
  }
  return Get.dialog(EntryDialog(entry: entry, customerId: customerId, date: date));
}

class EntryDialog extends StatefulWidget {
  final Entry? entry;
  final String? customerId;
  final DateTime? date;
  const EntryDialog({super.key, this.entry, this.customerId, this.date});

  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final c = Get.find<TallyController>();
  final _form = GlobalKey<FormState>();

  String? _customerId;
  String? _product;
  String? _paymentMode; // optional
  late DateTime _date;
  final _qty = TextEditingController();
  final _rate = TextEditingController(); // price per kg, when typed directly
  // Price per kg from the formula: percent × rate ÷ divisor (Settings)
  bool _useFormula = true;
  final _percent = TextEditingController();
  final _baseRate = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController(); // only when editing
  String? _reasonError;
  String? _customerError;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      _customerId = e.customerId;
      _date = e.date;
      _product = e.product.isEmpty ? null : c.addProduct(e.product);
      _paymentMode = e.paymentMode.isEmpty ? null : c.addPaymentMode(e.paymentMode);
      _qty.text = e.qty == 0 ? '' : numText(e.qty);
      _rate.text = e.rate == 0 ? '' : numText(e.rate);
      if (e.percent != null && e.baseRate != null) {
        _percent.text = numText(e.percent!);
        _baseRate.text = numText(e.baseRate!);
      } else if (e.qty > 0) {
        _useFormula = false; // this price was typed directly
      }
      _paid.text = e.paid == 0 ? '' : numText(e.paid);
      _note.text = e.note;
    } else {
      _customerId = widget.customerId;
      _date = widget.date ?? dateOnly(DateTime.now());
      _fillRate(_customerId);
    }
  }

  /// New entry: formula or typed price, as this product was priced last
  /// time (formula unless it was typed directly). Then fills percent and rate
  /// (or the price) from this customer's last sale of the product.
  void _fillRate(String? id) {
    _useFormula = !c.priceTypedFor(_product);
    if (id == null) return;
    final last = c.lastSale(id, _product);
    if (last == null) return;
    if (last.percent != null && last.baseRate != null) {
      _percent.text = numText(last.percent!);
      _baseRate.text = numText(last.baseRate!);
    }
    _rate.text = last.rate == 0 ? '' : numText(last.rate);
  }

  /// Price per kg: from the formula, or as typed.
  double get _price => _useFormula
      ? priceFromFormula(
          parseNum(_percent.text), parseNum(_baseRate.text), c.priceDivisor.value)
      : parseNum(_rate.text);

  /// e.g. "Last: 82.5% × ₹8,000 = ₹497.74 on 10 Nov 2026" for this customer + product.
  String? _lastPriceText() {
    if (_customerId == null || _product == null) return null;
    final last = c
        .entriesOf(_customerId!)
        .where((e) => e.qty > 0 && e.product == _product && e.id != widget.entry?.id)
        .lastOrNull;
    if (last == null) return 'First sale of this product to this customer';
    final how = last.percent == null || last.baseRate == null
        ? ''
        : '${pctText(last.percent!)} × ${money(last.baseRate!)} = ';
    return 'Last: $how${perKg(last.rate)}/kg on ${shortDate(last.date)}';
  }

  /// "+" button: asks for a new product name and selects it.
  Future<void> _addProduct() async {
    final name = await _askName('New product', 'Product name');
    if (name == null) return;
    setState(() {
      _product = c.addProduct(name.trim());
      if (widget.entry == null) _fillRate(_customerId);
    });
  }

  /// "+" button next to Payment mode.
  Future<void> _addPaymentMode() async {
    final name = await _askName('New payment mode', 'e.g. Cheque, Credit card');
    if (name == null) return;
    setState(() => _paymentMode = c.addPaymentMode(name));
  }

  /// Small popup asking for a name. Returns null if cancelled or empty.
  Future<String?> _askName(String title, String label) async {
    final text = TextEditingController();
    final name = await Get.dialog<String>(AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Get.back(result: v),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Get.back(result: text.text), child: const Text('Add')),
      ],
    ));
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  void _save() {
    final formOk = _form.currentState!.validate();
    setState(() => _customerError = _customerId == null ? 'Choose a customer' : null);
    if (!formOk || _customerId == null) return;
    final qty = parseNum(_qty.text);
    final paid = parseNum(_paid.text);
    if (qty <= 0 && paid <= 0) {
      Get.snackbar('Nothing to save', 'Enter a quantity sold or an amount paid.',
          snackPosition: SnackPosition.BOTTOM, maxWidth: 500);
      return;
    }
    final product = qty > 0 ? (_product ?? '') : '';
    final rate = qty > 0 ? _price : 0.0;
    final formula = qty > 0 && _useFormula;
    final percent = formula ? parseNum(_percent.text) : null;
    final baseRate = formula ? parseNum(_baseRate.text) : null;

    // Editing: nothing changed -> just close. Changed -> reason is required.
    final old = widget.entry;
    if (old != null) {
      final changes = c.entryChanges(
          old,
          Entry(
            id: old.id,
            customerId: _customerId!,
            date: dateOnly(_date),
            product: product,
            qty: qty,
            rate: rate,
            percent: percent,
            baseRate: baseRate,
            paid: paid,
            paymentMode: paid > 0 ? (_paymentMode ?? '') : '',
            note: _note.text.trim(),
          ));
      if (changes.isEmpty) {
        Get.back();
        return;
      }
      if (_reason.text.trim().isEmpty) {
        setState(() => _reasonError = 'Write why you are changing this entry');
        return;
      }
    }

    c.saveEntry(
      id: old?.id,
      customerId: _customerId!,
      date: _date,
      product: product,
      qty: qty,
      rate: rate,
      percent: percent,
      baseRate: baseRate,
      paid: paid,
      paymentMode: _paymentMode ?? '',
      note: _note.text.trim(),
      reason: _reason.text.trim(),
    );
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final saleAmount = parseNum(_qty.text) * _price;
    final divisor = c.priceDivisor.value;
    bool selling() => parseNum(_qty.text) > 0;

    return AlertDialog(
      title: Text(widget.entry == null ? 'New entry' : 'Edit entry'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Searchable: type a name, code, area, district or state
                CustomerPicker(
                  value: _customerId,
                  label: 'Customer *',
                  errorText: _customerError,
                  onChanged: (v) => setState(() {
                    _customerId = v;
                    _customerError = null;
                    if (v != null && widget.entry == null) _fillRate(v);
                  }),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(longDate(_date)),
                ),
                const SizedBox(height: 20),
                Text('Sale', style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_product), // refresh after adding a product
                        initialValue: _product,
                        decoration: const InputDecoration(labelText: 'Product'),
                        items: [
                          for (final p in c.products)
                            DropdownMenuItem(value: p, child: Text(p)),
                        ],
                        onChanged: (v) => setState(() {
                          _product = v;
                          if (widget.entry == null) _fillRate(_customerId);
                        }),
                        validator: (v) => parseNum(_qty.text) > 0 && v == null
                            ? 'Choose a product'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Add new product',
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qty,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Quantity (kg)'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_useFormula) ...[
                      Expanded(
                        child: TextFormField(
                          controller: _percent,
                          decoration: const InputDecoration(labelText: 'Percent (%)'),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => selling() && parseNum(v ?? '') <= 0
                              ? 'Enter the percent'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _baseRate,
                          decoration: const InputDecoration(labelText: 'Rate (₹)'),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => selling() && parseNum(v ?? '') <= 0
                              ? 'Enter the rate'
                              : null,
                        ),
                      ),
                    ] else
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _rate,
                          decoration: const InputDecoration(labelText: 'Price per kg (₹)'),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => selling() && parseNum(v ?? '') <= 0
                              ? 'Enter the price'
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // How the price per kg is worked out
                if (_useFormula)
                  Text(
                    parseNum(_percent.text) > 0 && parseNum(_baseRate.text) > 0
                        ? 'Price per kg = ${numText(parseNum(_percent.text))} × '
                            '${money(parseNum(_baseRate.text))} ÷ ${numText(divisor)} = '
                            '${perKg(_price)}'
                        : 'Price per kg = Percent × Rate ÷ ${numText(divisor)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (_lastPriceText() != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_lastPriceText()!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() {
                      if (_useFormula && _price > 0) _rate.text = numText(_price);
                      _useFormula = !_useFormula;
                    }),
                    child: Text(_useFormula
                        ? 'Type price per kg instead'
                        : 'Use the formula (percent × rate ÷ ${numText(divisor)})'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Sale amount: ${moneyExact(saleAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text('Payment', style: Theme.of(context).textTheme.titleSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _paid,
                        decoration: const InputDecoration(labelText: 'Amount paid (₹)'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('mode-$_paymentMode'), // refresh after adding
                        initialValue: _paymentMode,
                        decoration:
                            const InputDecoration(labelText: 'Payment mode (optional)'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('— Not set —')),
                          for (final m in c.paymentModes)
                            DropdownMenuItem<String?>(value: m, child: Text(m)),
                        ],
                        onChanged: (v) => setState(() => _paymentMode = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Add new payment mode',
                      onPressed: _addPaymentMode,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                  onFieldSubmitted: (_) => _save(),
                ),
                if (widget.entry != null) ...[
                  const SizedBox(height: 20),
                  ReasonField(controller: _reason, errorText: _reasonError),
                  if (c.wasEdited(widget.entry!.id))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => showEntryHistory(widget.entry!.id),
                        icon: const Icon(Icons.history, size: 18),
                        label: Text(
                            'See earlier changes (${c.historyOfEntry(widget.entry!.id).length})'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
