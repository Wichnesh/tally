// Data models: a Customer and a daily Entry (sale and/or payment).

class Customer {
  final String id;
  String code; // unique customer code, e.g. 1001 (names can repeat)
  String name;
  String phone;
  String location; // area / town / street (free text)
  String district; // typed by the user, e.g. Erode
  String state; // one of indianStates, or '' if not set
  List<String> proofs; // saved file paths of ID / document copies (optional)

  // From the shop's old (paper) book, before using this app. Counted in the
  // customer's totals and balance, not in any day's sales or cash.
  double openingBought; // total purchases before
  double openingPaid; // total paid before
  DateTime? openingDate; // "as on" date of those figures

  double get openingBalance => openingBought - openingPaid;
  bool get hasOpening => openingBought != 0 || openingPaid != 0;

  Customer({
    required this.id,
    this.code = '',
    required this.name,
    this.phone = '',
    this.location = '',
    this.district = '',
    this.state = '',
    List<String>? proofs,
    this.openingBought = 0,
    this.openingPaid = 0,
    this.openingDate,
  }) : proofs = proofs ?? [];

  /// Name with code, e.g. "Ravi Stores · #1001". Used in lists and tables.
  String get label => code.isEmpty ? name : '$name · #$code';

  /// Where the customer is, e.g. "Perundurai, Erode, Tamil Nadu" ('' if unknown).
  String get place =>
      [location, district, state].where((x) => x.trim().isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'phone': phone,
        'location': location,
        'district': district,
        'state': state,
        'proofs': proofs,
        'openingBought': openingBought,
        'openingPaid': openingPaid,
        'openingDate': openingDate?.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'],
        code: j['code'] ?? '',
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        location: j['location'] ?? '',
        district: j['district'] ?? '',
        state: j['state'] ?? '',
        proofs: List<String>.from(j['proofs'] ?? []),
        openingBought: (j['openingBought'] ?? 0).toDouble(),
        openingPaid: (j['openingPaid'] ?? 0).toDouble(),
        openingDate: j['openingDate'] == null ? null : DateTime.parse(j['openingDate']),
      );
}

/// One line in the tally. A customer can buy ghee (qty x rate)
/// and pay money on the same entry. Either part can be zero.
class Entry {
  final String id;
  String customerId;
  DateTime date;
  String product; // e.g. Yellow Ghee (empty for payment-only entries)
  double qty; // kg
  double rate; // price per kg
  // When the price comes from the formula  percent × rate ÷ divisor
  // (null when the price per kg was typed directly)
  double? percent;
  double? baseRate;
  double paid; // money received
  String paymentMode; // optional: Cash, UPI, Bank transfer, ...
  String note;

  Entry({
    required this.id,
    required this.customerId,
    required this.date,
    this.product = '',
    this.qty = 0,
    this.rate = 0,
    this.percent,
    this.baseRate,
    this.paid = 0,
    this.paymentMode = '',
    this.note = '',
  });

  double get amount => qty * rate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'product': product,
        'qty': qty,
        'rate': rate,
        'percent': percent,
        'baseRate': baseRate,
        'paid': paid,
        'paymentMode': paymentMode,
        'note': note,
      };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'],
        customerId: j['customerId'],
        date: DateTime.parse(j['date']),
        product: j['product'] ?? '',
        qty: (j['qty'] ?? 0).toDouble(),
        rate: (j['rate'] ?? 0).toDouble(),
        percent: (j['percent'] as num?)?.toDouble(),
        baseRate: (j['baseRate'] as num?)?.toDouble(),
        paid: (j['paid'] ?? 0).toDouble(),
        paymentMode: j['paymentMode'] ?? '',
        note: j['note'] ?? '',
      );
}

/// One field that changed: e.g. Qty  200 kg -> 180 kg.
class Change {
  final String field;
  final String from;
  final String to;
  Change(this.field, this.from, this.to);

  Map<String, dynamic> toJson() => {'field': field, 'from': from, 'to': to};
  factory Change.fromJson(Map<String, dynamic> j) =>
      Change(j['field'] ?? '', j['from'] ?? '', j['to'] ?? '');
}

/// A record of an edit or delete, with the reason the user gave.
class HistoryItem {
  final String id;
  final DateTime at; // when the change was made
  final String kind; // 'entry' or 'customer'
  final String action; // 'edited' or 'deleted'
  final String targetId; // entry id or customer id
  final String customerId;
  final String customerLabel; // "Ravi Stores · #1001" at the time of change
  final String what; // e.g. "Entry of 10 Nov 2026"
  final List<Change> changes;
  final String reason;

  HistoryItem({
    required this.id,
    required this.at,
    required this.kind,
    required this.action,
    required this.targetId,
    required this.customerId,
    required this.customerLabel,
    required this.what,
    required this.changes,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'kind': kind,
        'action': action,
        'targetId': targetId,
        'customerId': customerId,
        'customerLabel': customerLabel,
        'what': what,
        'changes': changes.map((c) => c.toJson()).toList(),
        'reason': reason,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: j['id'],
        at: DateTime.parse(j['at']),
        kind: j['kind'] ?? 'entry',
        action: j['action'] ?? 'edited',
        targetId: j['targetId'] ?? '',
        customerId: j['customerId'] ?? '',
        customerLabel: j['customerLabel'] ?? '',
        what: j['what'] ?? '',
        changes: ((j['changes'] as List?) ?? [])
            .map((x) => Change.fromJson(Map<String, dynamic>.from(x)))
            .toList(),
        reason: j['reason'] ?? '',
      );
}

/// One cash-book line that is not a customer payment:
///  - 'expense'  money paid out of [account] (EB, rent, salary...)
///  - 'income'   other money coming into [account] (owner, loan...)
///  - 'transfer' money moved from [account] to [toAccount] (cash to bank)
///  - 'opening'  balance counted / checked in [account] when the shop opened
class CashTxn {
  static const expense = 'expense';
  static const income = 'income';
  static const transfer = 'transfer';
  static const opening = 'opening';

  final String id;
  String type;
  DateTime date;
  String account;
  String toAccount; // transfers only
  String category; // expense category or income source ('' for others)
  double amount;
  String note;

  CashTxn({
    required this.id,
    required this.type,
    required this.date,
    required this.account,
    this.toAccount = '',
    this.category = '',
    required this.amount,
    this.note = '',
  });

  String get typeLabel => switch (type) {
        expense => 'Expense',
        income => 'Money in',
        transfer => 'Transfer',
        _ => 'Opening balance',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'date': date.toIso8601String(),
        'account': account,
        'toAccount': toAccount,
        'category': category,
        'amount': amount,
        'note': note,
      };

  factory CashTxn.fromJson(Map<String, dynamic> j) => CashTxn(
        id: j['id'],
        type: j['type'] ?? expense,
        date: DateTime.parse(j['date']),
        account: j['account'] ?? '',
        toAccount: j['toAccount'] ?? '',
        category: j['category'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        note: j['note'] ?? '',
      );
}
