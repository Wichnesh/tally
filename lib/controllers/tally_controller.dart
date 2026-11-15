import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../services/app_data.dart';
import '../utils.dart';

/// Holds all customers, entries and settings.
/// Everything is saved automatically to a local file (GetStorage).
class TallyController extends GetxController {
  final _box = GetStorage();

  final customers = <Customer>[].obs;
  final entries = <Entry>[].obs;

  // Product list for the dropdown. New products can be added with the + button.
  static const defaultProducts = [
    'Dust',
    'Yellow Ghee',
    'White Butter',
    'Yellow Butter',
    'Curd',
    'Buttermilk',
  ];
  final products = <String>[].obs;

  /// Products renamed after the app was in use (old name -> new name).
  /// Saved data and old backups still have the old name; it is changed when
  /// they are loaded (see [_renameOldProducts]).
  static const renamedProducts = {'Dust White Ghee': 'Dust'};

  // Payment modes for the optional dropdown. More can be added with +.
  static const defaultPaymentModes = ['Cash', 'UPI', 'Bank transfer'];
  final paymentModes = <String>[].obs;

  // Every edit / delete, with the reason. Newest last.
  final history = <HistoryItem>[].obs;

  // ----- Cash book -----
  // Where money is kept. More can be added (e.g. a second bank).
  static const defaultAccounts = ['Cash', 'Bank'];
  final accounts = <String>[].obs;

  /// Which account each payment mode goes to (e.g. UPI -> Bank).
  final modeAccounts = <String, String>{}.obs;

  static const defaultExpenseCategories = [
    'EB (Electricity)',
    'Rent',
    'Salary / Wages',
    'Milk / Raw material',
    'Transport / Diesel',
    'Packing material',
    'Repairs',
    'Tea / Snacks',
    'Other',
  ];
  final expenseCategories = <String>[].obs;

  static const defaultIncomeSources = ['Owner added money', 'Loan', 'Other income'];
  final incomeSources = <String>[].obs;

  /// Expenses, other money in, transfers and opening balances.
  final cashTxns = <CashTxn>[].obs;

  // Global alert levels (in % of sales that has been paid).
  // Paid % below redBelow      -> RED
  // Paid % from greenFrom up   -> GREEN
  // Anything in between        -> YELLOW
  final redBelow = 40.0.obs;
  final greenFrom = 75.0.obs;

  /// Price per kg = percent × rate ÷ [priceDivisor] (set in Settings).
  static const defaultPriceDivisor = 1326.0;
  final priceDivisor = defaultPriceDivisor.obs;

  /// Products whose last sale had the price per kg typed directly (not the
  /// formula). The entry form opens in that mode for them next time.
  final manualPriceProducts = <String>{}.obs;

  bool priceTypedFor(String? product) =>
      product != null && manualPriceProducts.contains(product);

  /// Goes up by one every time data is saved. The backup service
  /// watches this to make a backup after every change.
  final changes = 0.obs;

  /// Set when the saved data could not be read (damaged file).
  String? loadProblem;

  bool get hasData => customers.isNotEmpty || entries.isNotEmpty || cashTxns.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    try {
      _load();
    } catch (e) {
      loadProblem = e.toString();
      customers.clear();
      entries.clear();
    }
  }

  // ---------- Load / Save ----------

  void _load() {
    final c = _box.read<List>('customers') ?? [];
    final e = _box.read<List>('entries') ?? [];
    customers.assignAll(
        c.map((x) => Customer.fromJson(Map<String, dynamic>.from(x))));
    entries.assignAll(e.map((x) => Entry.fromJson(Map<String, dynamic>.from(x))));
    products.assignAll(
        (_box.read<List>('products') ?? defaultProducts).map((x) => x.toString()));
    paymentModes.assignAll((_box.read<List>('paymentModes') ?? defaultPaymentModes)
        .map((x) => x.toString()));
    history.assignAll((_box.read<List>('history') ?? [])
        .map((x) => HistoryItem.fromJson(Map<String, dynamic>.from(x))));
    _loadCashBook({
      'accounts': _box.read('accounts'),
      'modeAccounts': _box.read('modeAccounts'),
      'expenseCategories': _box.read('expenseCategories'),
      'incomeSources': _box.read('incomeSources'),
      'cashTxns': _box.read('cashTxns'),
    });
    redBelow.value = (_box.read('redBelow') ?? 40).toDouble();
    greenFrom.value = (_box.read('greenFrom') ?? 75).toDouble();
    priceDivisor.value = (_box.read('priceDivisor') ?? defaultPriceDivisor).toDouble();
    manualPriceProducts.assignAll(List<String>.from(_box.read('manualPriceProducts') ?? []));
    if (_renameOldProducts()) _save();
    _giveMissingCodes(); // after everything is loaded, because it saves
  }

  /// Applies [renamedProducts] to the product list, the entries and
  /// [manualPriceProducts]. Only while the list has the old name and not the
  /// new one, so a product added later with the old name is left alone.
  /// Returns true if anything was renamed.
  bool _renameOldProducts() {
    var renamed = false;
    renamedProducts.forEach((old, now) {
      if (!products.contains(old) || products.contains(now)) return;
      products[products.indexOf(old)] = now;
      for (final e in entries.where((e) => e.product == old)) {
        e.product = now;
      }
      if (manualPriceProducts.remove(old)) manualPriceProducts.add(now);
      renamed = true;
    });
    if (renamed) entries.refresh();
    return renamed;
  }

  void _save() {
    _box.write('customers', customers.map((c) => c.toJson()).toList());
    _box.write('entries', entries.map((e) => e.toJson()).toList());
    _box.write('products', products.toList());
    _box.write('paymentModes', paymentModes.toList());
    _box.write('history', history.map((h) => h.toJson()).toList());
    _cashBookData().forEach(_box.write);
    _box.write('redBelow', redBelow.value);
    _box.write('greenFrom', greenFrom.value);
    _box.write('priceDivisor', priceDivisor.value);
    _box.write('manualPriceProducts', manualPriceProducts.toList());
    changes.value++;
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ---------- Customers ----------

  Customer? customerById(String id) =>
      customers.firstWhereOrNull((c) => c.id == id);

  /// "Name · #code" for showing in lists and tables.
  String customerName(String id) => customerById(id)?.label ?? 'Deleted customer';

  /// State last picked for a customer (pre-filled for a new one). Editing a
  /// customer without changing their state does not change it.
  String get lastState => _box.read<String>('lastState') ?? '';

  /// States that customers are in, A-Z ('' = some customers have no state).
  List<String> statesInUse() {
    final set = <String>{for (final c in customers) c.state};
    return set.toList()..sort(_notSetLast);
  }

  /// Districts typed for customers in [state] (all states if null), A-Z.
  /// Spellings that differ only in capitals are shown once.
  /// '' is included when some of those customers have no district.
  List<String> districtsIn(String? state) {
    final byKey = <String, String>{};
    for (final c in customers) {
      if (state != null && c.state != state) continue;
      byKey.putIfAbsent(c.district.trim().toLowerCase(), () => c.district.trim());
    }
    return byKey.values.toList()..sort(_notSetLast);
  }

  static int _notSetLast(String a, String b) {
    if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  bool isCodeTaken(String code, {String? exceptId}) => customers.any((c) =>
      c.id != exceptId && c.code.toLowerCase() == code.trim().toLowerCase());

  /// Next free number code: highest number code + 1, starting at 1001.
  String nextCode() {
    var max = 1000;
    for (final c in customers) {
      final n = int.tryParse(c.code);
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  /// Customers saved before codes existed get one, in the order they were added.
  void _giveMissingCodes() {
    final missing = customers.where((c) => c.code.isEmpty).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (missing.isEmpty) return;
    for (final c in missing) {
      c.code = nextCode();
    }
    _save();
  }

  void _sortCustomers() => customers.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.code.compareTo(b.code);
      });

  /// Adds a new customer (when [existing] is null) or updates one.
  /// [proofs] is the final list of proof files: files already saved are kept,
  /// newly picked files are copied into the app's "proofs" folder,
  /// and saved files no longer in the list are deleted.
  Future<void> saveCustomer({
    Customer? existing,
    required String code,
    required String name,
    required String phone,
    required String location,
    String district = '',
    String state = '',
    required List<String> proofs,
    double openingBought = 0,
    double openingPaid = 0,
    DateTime? openingDate,
    String reason = '', // required by the form when editing
  }) async {
    if (openingBought == 0 && openingPaid == 0) openingDate = null;
    district = district.trim();
    final stateChosen = state.isNotEmpty && (existing == null || existing.state != state);
    final before = existing == null ? null : customerFields(existing);
    final dir = await proofsDir();
    final finalProofs = <String>[];
    for (final path in proofs) {
      if (p.isWithin(dir.path, path)) {
        finalProofs.add(path); // already saved
      } else {
        final target = p.join(dir.path, '${_newId()}_${p.basename(path)}');
        await File(path).copy(target);
        finalProofs.add(target);
      }
    }
    for (final old in existing?.proofs ?? <String>[]) {
      if (!finalProofs.contains(old)) _deleteFile(old);
    }

    if (existing == null) {
      customers.add(Customer(
        id: _newId(),
        code: code,
        name: name,
        phone: phone,
        location: location,
        district: district,
        state: state,
        proofs: finalProofs,
        openingBought: openingBought,
        openingPaid: openingPaid,
        openingDate: openingDate,
      ));
    } else {
      existing
        ..code = code
        ..name = name
        ..phone = phone
        ..location = location
        ..district = district
        ..state = state
        ..proofs = finalProofs
        ..openingBought = openingBought
        ..openingPaid = openingPaid
        ..openingDate = openingDate;
      final changes = diff(before!, customerFields(existing));
      if (changes.isNotEmpty) {
        _log(
          kind: 'customer',
          action: 'edited',
          targetId: existing.id,
          customerId: existing.id,
          customerLabel: existing.label,
          what: 'Customer details',
          changes: changes,
          reason: reason,
        );
      }
    }
    _sortCustomers();
    customers.refresh();
    // Default State for the next new customer: only when a state was actually
    // picked (new customer, or the state of an existing one was changed).
    if (stateChosen) _box.write('lastState', state);
    _save();
  }

  /// Deletes the customer, their proof files and all of their entries.
  void deleteCustomer(String id, {String reason = ''}) {
    final cu = customerById(id);
    if (cu == null) return;
    final count = entries.where((e) => e.customerId == id).length;
    _log(
      kind: 'customer',
      action: 'deleted',
      targetId: id,
      customerId: id,
      customerLabel: cu.label,
      what: 'Customer and $count entries',
      changes: [
        for (final f in customerFields(cu).entries) Change(f.key, f.value, ''),
        Change('Total bought', money(soldOf(id)), ''),
        Change('Total paid', money(paidOf(id)), ''),
      ],
      reason: reason,
    );
    cu.proofs.forEach(_deleteFile);
    customers.removeWhere((c) => c.id == id);
    entries.removeWhere((e) => e.customerId == id);
    _save();
  }

  Future<Directory> proofsDir() async {
    final dir = await appDataDir(); // next to the data file
    return Directory(p.join(dir.path, 'proofs')).create(recursive: true);
  }

  void _deleteFile(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {} // already gone
  }

  // ---------- Products ----------

  /// Adds a product to the dropdown. Returns the saved name
  /// (the existing one if it is already in the list).
  String addProduct(String name) {
    final existing = products
        .firstWhereOrNull((p) => p.toLowerCase() == name.toLowerCase());
    if (existing != null) return existing;
    products.add(name);
    _save();
    return name;
  }

  /// Adds a payment mode to the dropdown. Returns the saved name
  /// (the existing one if it is already in the list).
  String addPaymentMode(String name) {
    final existing = paymentModes
        .firstWhereOrNull((m) => m.toLowerCase() == name.toLowerCase());
    if (existing != null) return existing;
    paymentModes.add(name);
    _save();
    return name;
  }

  // ---------- Entries ----------

  /// Adds a new entry, or replaces it if the id already exists.
  void saveEntry({
    String? id,
    required String customerId,
    required DateTime date,
    String product = '',
    required double qty,
    required double rate,
    double? percent, // with baseRate: price came from the formula
    double? baseRate,
    required double paid,
    String paymentMode = '',
    String note = '',
    String reason = '', // required by the form when editing
  }) {
    final formula = qty > 0 && percent != null && baseRate != null;
    // Remember how this product was priced, for the next entry
    if (qty > 0 && product.isNotEmpty) {
      formula ? manualPriceProducts.remove(product) : manualPriceProducts.add(product);
    }
    final entry = Entry(
      id: id ?? _newId(),
      customerId: customerId,
      date: dateOnly(date),
      product: product,
      qty: qty,
      rate: rate,
      percent: formula ? percent : null,
      baseRate: formula ? baseRate : null,
      paid: paid,
      paymentMode: paid > 0 ? paymentMode : '',
      note: note,
    );
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      final changes = entryChanges(entries[i], entry);
      if (changes.isNotEmpty) {
        _log(
          kind: 'entry',
          action: 'edited',
          targetId: entry.id,
          customerId: entry.customerId,
          customerLabel: customerName(entry.customerId),
          what: 'Entry of ${shortDate(entries[i].date)}',
          changes: changes,
          reason: reason,
        );
      }
      entries[i] = entry;
    } else {
      entries.add(entry);
    }
    _save();
  }

  void deleteEntry(String id, {String reason = ''}) {
    final e = entries.firstWhereOrNull((e) => e.id == id);
    if (e == null) return;
    _log(
      kind: 'entry',
      action: 'deleted',
      targetId: id,
      customerId: e.customerId,
      customerLabel: customerName(e.customerId),
      what: 'Entry of ${shortDate(e.date)}',
      changes: [for (final f in entryFields(e).entries) Change(f.key, f.value, '')],
      reason: reason,
    );
    entries.removeWhere((e) => e.id == id);
    _save();
  }

  // ---------- Change history ----------

  /// The fields of an entry as readable text, for comparing.
  Map<String, String> entryFields(Entry e) => {
        'Customer': customerName(e.customerId),
        'Date': shortDate(e.date),
        'Product': e.product.isEmpty ? '-' : e.product,
        'Qty': kg(e.qty),
        'Percent': e.percent == null ? '-' : pctText(e.percent!),
        'Rate': e.baseRate == null ? '-' : money(e.baseRate!),
        'Price/kg': perKg(e.rate),
        'Sale': money(e.amount),
        'Paid': money(e.paid),
        'Payment mode': e.paymentMode.isEmpty ? '-' : e.paymentMode,
        'Note': e.note.isEmpty ? '-' : e.note,
      };

  Map<String, String> customerFields(Customer c) => {
        'Code': c.code,
        'Name': c.name,
        'Phone': c.phone.isEmpty ? '-' : c.phone,
        'Area / Town': c.location.isEmpty ? '-' : c.location,
        'District': c.district.isEmpty ? '-' : c.district,
        'State': c.state.isEmpty ? '-' : c.state,
        // File names without the number prefix added when saving
        'Proofs': c.proofs.isEmpty
            ? '-'
            : c.proofs
                .map((x) => p.basename(x).replaceFirst(RegExp(r'^\d+_'), ''))
                .join(', '),
        'Old book: purchases': money(c.openingBought),
        'Old book: paid': money(c.openingPaid),
        'Old book: as on': c.openingDate == null ? '-' : shortDate(c.openingDate!),
      };

  List<Change> diff(Map<String, String> before, Map<String, String> after) => [
        for (final k in before.keys)
          if (before[k] != after[k]) Change(k, before[k]!, after[k] ?? ''),
      ];

  List<Change> entryChanges(Entry before, Entry after) =>
      diff(entryFields(before), entryFields(after));

  /// History of one customer (their details and all their entries), newest first.
  List<HistoryItem> historyOfCustomer(String customerId) =>
      history.where((h) => h.customerId == customerId).toList().reversed.toList();

  /// History of one entry, newest first.
  List<HistoryItem> historyOfEntry(String entryId) =>
      history.where((h) => h.targetId == entryId).toList().reversed.toList();

  bool wasEdited(String entryId) => history.any((h) => h.targetId == entryId);

  void _log({
    required String kind,
    required String action,
    required String targetId,
    required String customerId,
    required String customerLabel,
    required String what,
    required List<Change> changes,
    required String reason,
  }) {
    history.add(HistoryItem(
      id: _newId(),
      at: DateTime.now(),
      kind: kind,
      action: action,
      targetId: targetId,
      customerId: customerId,
      customerLabel: customerLabel,
      what: what,
      changes: changes,
      reason: reason,
    ));
  }

  /// All entries of one customer, oldest first.
  List<Entry> entriesOf(String customerId) =>
      entries.where((e) => e.customerId == customerId).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<Entry> entriesOn(DateTime day) =>
      entries.where((e) => sameDay(e.date, day)).toList()
        ..sort((a, b) => customerName(a.customerId).compareTo(customerName(b.customerId)));

  /// The last sale to this customer of this product (any product if null).
  Entry? lastSale(String customerId, [String? product]) => entriesOf(customerId)
      .where((e) => e.qty > 0 && (product == null || e.product == product))
      .lastOrNull;

  /// Price to suggest for a new entry: the last price this customer paid
  /// for this product. 0 (empty) if they never bought it.
  double suggestedRate(String customerId, [String? product]) =>
      lastSale(customerId, product)?.rate ?? 0;

  // ---------- Totals & status ----------

  // Customer totals include the figures from the old book (opening).

  double soldOf(String id) =>
      (customerById(id)?.openingBought ?? 0) +
      entries.where((e) => e.customerId == id).fold(0.0, (s, e) => s + e.amount);

  double paidOf(String id) =>
      (customerById(id)?.openingPaid ?? 0) +
      entries.where((e) => e.customerId == id).fold(0.0, (s, e) => s + e.paid);

  double balanceOf(String id) => soldOf(id) - paidOf(id);

  double get totalSold =>
      customers.fold(0.0, (s, c) => s + c.openingBought) +
      entries.fold(0.0, (s, e) => s + e.amount);
  double get totalPaid =>
      customers.fold(0.0, (s, c) => s + c.openingPaid) +
      entries.fold(0.0, (s, e) => s + e.paid);

  /// Paid as % of sold. Null when nothing was sold yet.
  double? percent(double sold, double paid) =>
      sold <= 0 ? null : (paid / sold * 100);

  double? percentOf(String id) => percent(soldOf(id), paidOf(id));

  PayStatus statusFor(double? pct) {
    if (pct == null) return PayStatus.none;
    if (pct < redBelow.value) return PayStatus.red;
    if (pct >= greenFrom.value) return PayStatus.green;
    return PayStatus.yellow;
  }

  PayStatus statusOf(String id) => statusFor(percentOf(id));

  // ---------- Backup / restore ----------

  /// Everything the app knows, as plain JSON (used for backups).
  Map<String, dynamic> exportData() => {
        'customers': customers.map((c) => c.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'products': products.toList(),
        'paymentModes': paymentModes.toList(),
        'history': history.map((h) => h.toJson()).toList(),
        ..._cashBookData(),
        'redBelow': redBelow.value,
        'greenFrom': greenFrom.value,
        'priceDivisor': priceDivisor.value,
        'manualPriceProducts': manualPriceProducts.toList(),
      };

  /// Replaces ALL current data with a backup.
  /// [proofFiles] maps proof file name -> file bytes.
  Future<void> importData(
      Map<String, dynamic> data, Map<String, List<int>> proofFiles) async {
    final dir = await proofsDir();
    for (final f in proofFiles.entries) {
      await File(p.join(dir.path, f.key)).writeAsBytes(f.value);
    }
    final list = (data['customers'] as List)
        .map((x) => Customer.fromJson(Map<String, dynamic>.from(x)))
        .toList();
    for (final cu in list) {
      // Point proofs at this computer's proofs folder
      cu.proofs = cu.proofs.map((x) => p.join(dir.path, p.basename(x))).toList();
    }
    customers.assignAll(list);
    _giveMissingCodes();
    _sortCustomers();
    entries.assignAll((data['entries'] as List)
        .map((x) => Entry.fromJson(Map<String, dynamic>.from(x))));
    products.assignAll(List<String>.from(data['products'] ?? defaultProducts));
    paymentModes
        .assignAll(List<String>.from(data['paymentModes'] ?? defaultPaymentModes));
    history.assignAll(((data['history'] as List?) ?? [])
        .map((x) => HistoryItem.fromJson(Map<String, dynamic>.from(x))));
    _loadCashBook(data);
    redBelow.value = (data['redBelow'] ?? 40).toDouble();
    greenFrom.value = (data['greenFrom'] ?? 75).toDouble();
    priceDivisor.value = (data['priceDivisor'] ?? defaultPriceDivisor).toDouble();
    manualPriceProducts.assignAll(List<String>.from(data['manualPriceProducts'] ?? []));
    _renameOldProducts(); // backups made before a product was renamed
    _save();
  }

  // ---------- Cash book ----------

  void _loadCashBook(Map<String, dynamic> d) {
    List<String> names(dynamic v, List<String> fallback) =>
        v == null ? [...fallback] : List<String>.from(v);
    accounts.assignAll(names(d['accounts'], defaultAccounts));
    modeAccounts.assignAll(Map<String, String>.from(d['modeAccounts'] ?? {}));
    expenseCategories.assignAll(names(d['expenseCategories'], defaultExpenseCategories));
    incomeSources.assignAll(names(d['incomeSources'], defaultIncomeSources));
    cashTxns.assignAll(((d['cashTxns'] as List?) ?? [])
        .map((x) => CashTxn.fromJson(Map<String, dynamic>.from(x))));
  }

  Map<String, dynamic> _cashBookData() => {
        'accounts': accounts.toList(),
        'modeAccounts': Map<String, String>.from(modeAccounts),
        'expenseCategories': expenseCategories.toList(),
        'incomeSources': incomeSources.toList(),
        'cashTxns': cashTxns.map((t) => t.toJson()).toList(),
      };

  /// Adds [name] to [list] unless it is there already (ignoring capitals).
  /// Returns the saved name.
  String _addName(RxList<String> list, String name) {
    final existing = list.firstWhereOrNull((x) => x.toLowerCase() == name.toLowerCase());
    if (existing != null) return existing;
    list.add(name);
    _save();
    return name;
  }

  String addAccount(String name) => _addName(accounts, name);
  String addExpenseCategory(String name) => _addName(expenseCategories, name);
  String addIncomeSource(String name) => _addName(incomeSources, name);

  /// The account a customer payment with this mode goes to.
  /// Set in Settings; otherwise a guess: "Cash" (and no mode) -> the cash
  /// account, anything else (UPI, bank transfer, cheque) -> the first other account.
  String accountForMode(String mode) {
    final set = modeAccounts[mode];
    if (set != null && set.isNotEmpty) return set;
    final cash = accounts.firstWhereOrNull((a) => a.toLowerCase().contains('cash')) ??
        (accounts.isEmpty ? 'Cash' : accounts.first);
    if (mode.isEmpty || mode.toLowerCase().contains('cash')) return cash;
    return accounts.firstWhereOrNull((a) => a != cash) ?? cash;
  }

  void setModeAccount(String mode, String account) {
    modeAccounts[mode] = account;
    _save();
  }

  Map<String, String> cashFields(CashTxn t) => {
        'Type': t.typeLabel,
        'Date': shortDate(t.date),
        if (t.type == CashTxn.transfer) ...{
          'From': t.account,
          'To': t.toAccount,
        } else ...{
          'Account': t.account,
        },
        if (t.type == CashTxn.expense || t.type == CashTxn.income)
          'Category': t.category.isEmpty ? '-' : t.category,
        'Amount': money(t.amount),
        'Note': t.note.isEmpty ? '-' : t.note,
      };

  String _cashWhat(CashTxn t) => '${t.typeLabel} of ${shortDate(t.date)}';

  /// Adds a cash-book line, or replaces it if the id exists. Edits are
  /// recorded in the change history with [reason].
  void saveCashTxn({
    String? id,
    required String type,
    required DateTime date,
    required String account,
    String toAccount = '',
    String category = '',
    required double amount,
    String note = '',
    String reason = '',
  }) {
    final t = CashTxn(
      id: id ?? _newId(),
      type: type,
      date: dateOnly(date),
      account: account,
      toAccount: type == CashTxn.transfer ? toAccount : '',
      category: (type == CashTxn.expense || type == CashTxn.income) ? category : '',
      amount: amount,
      note: note.trim(),
    );
    final i = cashTxns.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      final changes = diff(cashFields(cashTxns[i]), cashFields(t));
      if (changes.isNotEmpty) {
        _log(
          kind: 'cash',
          action: 'edited',
          targetId: t.id,
          customerId: '',
          customerLabel: 'Cash book',
          what: _cashWhat(cashTxns[i]),
          changes: changes,
          reason: reason,
        );
      }
      cashTxns[i] = t;
    } else {
      cashTxns.add(t);
    }
    _save();
  }

  void deleteCashTxn(String id, {String reason = ''}) {
    final t = cashTxns.firstWhereOrNull((x) => x.id == id);
    if (t == null) return;
    _log(
      kind: 'cash',
      action: 'deleted',
      targetId: id,
      customerId: '',
      customerLabel: 'Cash book',
      what: _cashWhat(t),
      changes: [for (final f in cashFields(t).entries) Change(f.key, f.value, '')],
      reason: reason,
    );
    cashTxns.removeWhere((x) => x.id == id);
    _save();
  }

  // ---------- Settings ----------

  void setPriceDivisor(double v) {
    if (v <= 0) return;
    priceDivisor.value = v;
    _save();
  }

  void setLevels(double red, double green) {
    redBelow.value = red;
    greenFrom.value = green;
    _save();
  }
}
