import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/tally_controller.dart';
import '../models.dart';
import '../services/cashbook.dart';
import '../utils.dart';
import 'customer_filter_bar.dart';
import 'entry_dialog.dart';
import 'history_view.dart';

/// Opens the form for a cash-book line.
/// [type] is CashTxn.expense / income / transfer / opening.
/// Pass [txn] to edit an existing line, [date] / [account] to pre-fill a new one.
Future<void> openCashDialog(String type, {CashTxn? txn, DateTime? date, String? account}) =>
    Get.dialog(CashDialog(type: txn?.type ?? type, txn: txn, date: date, account: account));

/// Small popup asking for a name. Returns null if cancelled or empty.
Future<String?> askName(String title, String label) async {
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
      FilledButton(onPressed: () => Get.back(result: text.text), child: const Text('Add')),
    ],
  ));
  if (name == null || name.trim().isEmpty) return null;
  return name.trim();
}

class CashDialog extends StatefulWidget {
  final String type;
  final CashTxn? txn;
  final DateTime? date;
  final String? account;
  const CashDialog({super.key, required this.type, this.txn, this.date, this.account});

  @override
  State<CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<CashDialog> {
  final c = Get.find<TallyController>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  late DateTime _date;
  String? _account;
  String? _toAccount;
  String? _category;
  String? _amountError, _accountError, _categoryError, _reasonError;

  // Money in from a customer: saved as a customer payment (an entry with
  // no sale), so their balance, the Dashboard and the Cash book all update.
  bool _fromCustomer = false;
  String? _customerId;
  String? _mode; // payment mode, decides the account (Cash, UPI -> Bank...)
  String? _customerError;

  bool get _editing => widget.txn != null;
  String get _type => widget.type;
  bool get _hasCategory =>
      (_type == CashTxn.expense || _type == CashTxn.income) && !_fromCustomer;
  List<String> get _categories =>
      _type == CashTxn.expense ? c.expenseCategories : c.incomeSources;

  @override
  void initState() {
    super.initState();
    final t = widget.txn;
    if (t != null) {
      _date = t.date;
      _account = t.account;
      _toAccount = t.toAccount.isEmpty ? null : t.toAccount;
      _category = t.category.isEmpty ? null : t.category;
      _amount.text = numText(t.amount);
      _note.text = t.note;
    } else {
      _date = widget.date ?? dateOnly(DateTime.now());
      // Usual defaults: expenses and money in use Cash; transfers go Cash -> Bank
      final cash = c.accountForMode('Cash');
      _account = widget.account ?? (c.accounts.contains(cash) ? cash : c.accounts.firstOrNull);
      if (_type == CashTxn.transfer) {
        _toAccount = c.accounts.firstWhereOrNull((a) => a != _account);
      }
      // New money in: customer payment first (the most common), if any customers
      if (_type == CashTxn.income && c.customers.isNotEmpty) _fromCustomer = true;
      _mode = c.paymentModes.contains('Cash') ? 'Cash' : null;
    }
  }

  /// Saves a customer payment as an entry with no sale.
  void _saveCustomerPayment(double amount) {
    setState(() {
      _customerError = _customerId == null ? 'Choose a customer' : null;
      _amountError = amount <= 0 ? 'Enter the amount' : null;
    });
    if (_customerError != null || _amountError != null) return;
    c.saveEntry(
      customerId: _customerId!,
      date: _date,
      qty: 0,
      rate: 0,
      paid: amount,
      paymentMode: _mode ?? '',
      note: _note.text.trim(),
    );
    Get.back();
    Get.snackbar('Payment saved',
        '${money(amount)} from ${c.customerName(_customerId!)} → ${c.accountForMode(_mode ?? '')}',
        snackPosition: SnackPosition.BOTTOM, maxWidth: 520);
  }

  Future<void> _addMode() async {
    final name = await askName('New payment mode', 'e.g. Cheque, Credit card');
    if (name == null) return;
    setState(() => _mode = c.addPaymentMode(name));
  }

  /// Customer, their balance, payment mode and the account it goes to.
  List<Widget> _customerFields() {
    final cu = _customerId == null ? null : c.customerById(_customerId!);
    return [
      CustomerPicker(
        value: _customerId,
        label: 'Customer *',
        errorText: _customerError,
        onChanged: (v) => setState(() {
          _customerId = v;
          _customerError = null;
        }),
      ),
      if (cu != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Balance due: ${money(c.balanceOf(cu.id))}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('mode-$_mode-${c.paymentModes.length}'),
            initialValue: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Payment mode'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— Not set —')),
              for (final m in c.paymentModes)
                DropdownMenuItem<String?>(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _mode = v),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Add new payment mode',
          onPressed: _addMode,
          icon: const Icon(Icons.add),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Goes to: ${c.accountForMode(_mode ?? '')} '
            '(change in Settings → Customer payments go to)',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      const SizedBox(height: 12),
    ];
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _title {
    final name = switch (_type) {
      CashTxn.expense => 'expense',
      CashTxn.income => 'money in',
      CashTxn.transfer => 'transfer',
      _ => 'opening balance',
    };
    return _editing ? 'Edit $name' : 'New $name';
  }

  /// For an opening balance: what the app expects, i.e. the account's
  /// closing at the end of the previous day.
  double? _expectedOpening() {
    if (_type != CashTxn.opening || _account == null) return null;
    final days = cashBook(
      accounts: c.accounts,
      movements: movementsFrom(c.entries, c.cashTxns, c.accountForMode),
      txns: c.cashTxns,
      from: _date,
      to: _date,
    );
    return days.first.accounts[_account]?.expected;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _addCategory() async {
    final name = await askName(
        _type == CashTxn.expense ? 'New expense type' : 'New money-in source',
        _type == CashTxn.expense ? 'e.g. Water bill, Internet' : 'e.g. Bank interest');
    if (name == null) return;
    setState(() => _category =
        _type == CashTxn.expense ? c.addExpenseCategory(name) : c.addIncomeSource(name));
  }

  Future<void> _addAccount(bool to) async {
    final name = await askName('New account', 'e.g. SBI current account, Petty cash');
    if (name == null) return;
    final saved = c.addAccount(name);
    setState(() => to ? _toAccount = saved : _account = saved);
  }

  void _save() {
    final amount = parseNum(_amount.text);
    if (_fromCustomer) return _saveCustomerPayment(amount);
    setState(() {
      _amountError = _type == CashTxn.opening
          ? (_amount.text.trim().isEmpty ? 'Enter the balance' : null)
          : (amount <= 0 ? 'Enter the amount' : null);
      _accountError = _account == null ? 'Choose an account' : null;
      if (_type == CashTxn.transfer) {
        if (_toAccount == null) _accountError = 'Choose both accounts';
        if (_toAccount != null && _toAccount == _account) {
          _accountError = 'From and To must be different accounts';
        }
      }
      _categoryError = _hasCategory && _category == null ? 'Choose a type' : null;
      _reasonError = null;
    });
    if ([_amountError, _accountError, _categoryError].any((e) => e != null)) return;

    // Editing: nothing changed -> just close. Changed -> a reason is required.
    final old = widget.txn;
    if (old != null) {
      final changed = c.diff(
          c.cashFields(old),
          c.cashFields(CashTxn(
            id: old.id,
            type: _type,
            date: _date,
            account: _account!,
            toAccount: _type == CashTxn.transfer ? _toAccount! : '',
            category: _hasCategory ? _category! : '',
            amount: amount,
            note: _note.text.trim(),
          )));
      if (changed.isEmpty) {
        Get.back();
        return;
      }
      if (_reason.text.trim().isEmpty) {
        setState(() => _reasonError = 'Write why you are changing this');
        return;
      }
    }

    c.saveCashTxn(
      id: old?.id,
      type: _type,
      date: _date,
      account: _account!,
      toAccount: _toAccount ?? '',
      category: _category ?? '',
      amount: amount,
      note: _note.text,
      reason: _reason.text.trim(),
    );
    Get.back();
  }

  /// The list, plus [value] if it is not in it (an old name), so the
  /// dropdown can still show what was saved.
  List<String> _withValue(List<String> list, String? value) =>
      value == null || list.contains(value) ? list : [...list, value];

  Widget _accountField({required bool to, required String label}) {
    final value = to ? _toAccount : _account;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$value-${c.accounts.length}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final a in _withValue(c.accounts, value))
              DropdownMenuItem(value: a, child: Text(a)),
          ],
          onChanged: (v) => setState(() => to ? _toAccount = v : _account = v),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'Add new account',
        onPressed: () => _addAccount(to),
        icon: const Icon(Icons.add),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final expected = _expectedOpening();

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(longDate(_date)),
              ),
              const SizedBox(height: 16),

              // Money in: a sale entry (opens the full entry form),
              // a customer payment only, or other money
              if (_type == CashTxn.income && !_editing) ...[
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 'sale',
                        label: Text('Sale entry'),
                        tooltip: 'Customer, product, quantity, price per kg, paid'),
                    ButtonSegment(
                        value: 'payment',
                        label: Text('Customer payment'),
                        tooltip: 'Only money paid by a customer'),
                    ButtonSegment(
                        value: 'other',
                        label: Text('Other money in'),
                        tooltip: 'Owner money, loan, other income'),
                  ],
                  selected: {_fromCustomer ? 'payment' : 'other'},
                  onSelectionChanged: (v) {
                    if (v.first == 'sale') {
                      // Switch to the full entry form, keeping the date and customer
                      final date = _date, customer = _customerId;
                      Get.back();
                      openEntryDialog(date: date, customerId: customer);
                      return;
                    }
                    setState(() {
                      _fromCustomer = v.first == 'payment';
                      _amountError = _accountError = _categoryError = _customerError = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (_fromCustomer) ..._customerFields(),

              // Expense type / money-in source
              if (_hasCategory) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('cat-$_category-${_categories.length}'),
                      initialValue: _category,
                      isExpanded: true,
                      menuMaxHeight: 420,
                      decoration: InputDecoration(
                        labelText: _type == CashTxn.expense ? 'Expense type *' : 'Source *',
                        errorText: _categoryError,
                      ),
                      items: [
                        for (final x in _withValue(_categories, _category))
                          DropdownMenuItem(value: x, child: Text(x)),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _type == CashTxn.expense ? 'Add new expense type' : 'Add new source',
                    onPressed: _addCategory,
                    icon: const Icon(Icons.add),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              // Accounts (a customer payment's account comes from its payment mode)
              if (_fromCustomer)
                const SizedBox.shrink()
              else if (_type == CashTxn.transfer) ...[
                _accountField(to: false, label: 'From account *'),
                const SizedBox(height: 12),
                _accountField(to: true, label: 'To account *'),
              ] else
                _accountField(
                  to: false,
                  label: switch (_type) {
                    CashTxn.expense => 'Paid from *',
                    CashTxn.income => 'Received into *',
                    _ => 'Account *',
                  },
                ),
              if (_accountError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_accountError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ),
              const SizedBox(height: 12),

              // Amount
              TextField(
                controller: _amount,
                autofocus: !_editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _type == CashTxn.opening
                      ? 'Balance when the shop opened (₹) *'
                      : _fromCustomer
                          ? 'Amount received (₹) *'
                          : 'Amount (₹) *',
                  errorText: _amountError,
                ),
                onSubmitted: (_) => _save(),
              ),
              if (expected != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                        'Expected from the previous closing: ${money(expected)}. '
                        'Enter what you counted / see in the account.',
                        style: t.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _amount.text = numText(expected)),
                    child: const Text('Use this'),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                onSubmitted: (_) => _save(),
              ),
              if (_editing) ...[
                const SizedBox(height: 20),
                ReasonField(controller: _reason, errorText: _reasonError),
              ],
            ],
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
