import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:ghee_tally/controllers/tally_controller.dart';
import 'package:ghee_tally/models.dart';
import 'package:ghee_tally/utils.dart';
import 'package:ghee_tally/services/backup_service.dart';
import 'package:ghee_tally/services/cashbook.dart';
import 'package:ghee_tally/services/excel_export.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points the app's documents folder at a temp folder for the test.
class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String dir;
  _FakePaths(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir; // Windows: appDataDir
}

/// Removes the test's temp folder. On Windows the app's data file is still
/// open at this point and cannot be deleted; the system cleans Temp later.
Future<void> _deleteTemp(Directory tmp) async {
  try {
    await tmp.delete(recursive: true);
  } on FileSystemException catch (_) {}
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('ghee_tally_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    BackupService.dirOverride = '${tmp.path}/backups';
    await GetStorage.init();
  });

  tearDownAll(() async {
    // Stop automatic backups (cancels the pending one), let a running one finish
    await Get.delete<BackupService>(force: true);
    await Future.delayed(const Duration(seconds: 1));
    await _deleteTemp(tmp);
  });

  group('old backup folder ("Ghee Tally Backups") is moved to the new one', () {
    final day1 = DateTime(2026, 11, 10, 9);
    final day2 = DateTime(2026, 11, 11, 9);
    final day3 = DateTime(2026, 11, 12, 9);

    File put(Directory dir, String name, String text, DateTime changed) =>
        File('${dir.path}/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(text)
          ..setLastModifiedSync(changed);

    test('new folder not there yet: everything moves, times kept', () async {
      final base = await tmp.createTemp('move1');
      final from = Directory('${base.path}/Ghee Tally Backups');
      final to = Directory('${base.path}/Tally Backups');
      put(from, 'daily_2026-11-10.gtb', 'd10', day1);
      put(from, 'manual_2026-11-11_090000.gtb', 'm11', day2);
      put(from, 'proofs/abc123/id.png.gtp', 'photo', day1);

      await BackupService.moveFolder(from, to);

      expect(from.existsSync(), isFalse);
      expect(File('${to.path}/daily_2026-11-10.gtb').readAsStringSync(), 'd10');
      expect(File('${to.path}/manual_2026-11-11_090000.gtb').lastModifiedSync(), day2);
      expect(File('${to.path}/proofs/abc123/id.png.gtp').readAsStringSync(), 'photo');
    });

    test('both folders have files: merged, newer copy kept, old folder removed', () async {
      final base = await tmp.createTemp('move2');
      final from = Directory('${base.path}/Ghee Tally Backups');
      final to = Directory('${base.path}/Tally Backups');
      put(from, 'daily_2026-11-10.gtb', 'old d10', day1);
      put(from, 'daily_2026-11-11.gtb', 'newer d11', day3);
      put(from, 'proofs/abc123/id.png.gtp', 'photo', day1);
      put(to, 'daily_2026-11-10.gtb', 'new d10', day2); // newer than the old one
      put(to, 'daily_2026-11-11.gtb', 'older d11', day2); // older than the old one

      await BackupService.moveFolder(from, to);

      expect(from.existsSync(), isFalse);
      expect(File('${to.path}/daily_2026-11-10.gtb').readAsStringSync(), 'new d10');
      expect(File('${to.path}/daily_2026-11-11.gtb').readAsStringSync(), 'newer d11');
      // Copied files keep their time, so "latest backup" stays right
      expect(File('${to.path}/daily_2026-11-11.gtb').lastModifiedSync(), day3);
      expect(File('${to.path}/proofs/abc123/id.png.gtp').lastModifiedSync(), day1);
      // No temporary files left behind
      expect(to.listSync(recursive: true).where((f) => f.path.endsWith('.moving')), isEmpty);
    });

    test('no old folder: nothing happens', () async {
      final base = await tmp.createTemp('move3');
      final to = Directory('${base.path}/Tally Backups');
      await BackupService.moveFolder(Directory('${base.path}/Ghee Tally Backups'), to);
      expect(to.existsSync(), isFalse);
    });
  });

  test('backup is encrypted, restores with the right password only', () async {
    final tally = Get.put(TallyController());
    await tally.saveCustomer(
        code: '1001',
        name: 'Ravi Stores', phone: '9876543210', location: 'Erode', proofs: []);
    final id = tally.customers.first.id;
    tally.saveEntry(
        customerId: id, date: DateTime(2026, 11, 10), product: 'Yellow Ghee',
        qty: 200, rate: 500, paid: 50000);

    final b = Get.put(BackupService());
    await b.setPassword('secret123');
    final file = (await b.backupNow())!;

    // The file must not contain readable data
    final raw = String.fromCharCodes(await file.readAsBytes());
    expect(raw.contains('Ravi'), isFalse);
    expect(raw.startsWith('GTB1'), isTrue);

    // Wrong password fails
    expect(() => b.readBackup(file.path, 'wrong'), throwsA(contains('Wrong password')));

    // Right password works and restores data
    final contents = await b.readBackup(file.path, 'secret123');
    expect(contents.customerCount, 1);
    expect(contents.entryCount, 1);

    tally.deleteCustomer(id);
    expect(tally.customers, isEmpty);
    await tally.importData(contents.data, contents.proofFiles);
    expect(tally.customers.first.name, 'Ravi Stores');
    expect(tally.soldOf(id), 100000);
    expect(tally.paidOf(id), 50000);

    // Excel export has the 7 sheets and the entry
    final xl = Excel.decodeBytes(buildExcel());
    expect(xl.tables.keys.toSet(), {'Customers', 'Entries', 'Products', 'Daily', 'Change history', 'Cash book', 'Expenses & money in'});
    final row = xl.tables['Entries']!.row(1);
    expect(row[1]!.value.toString(), '1001');
    expect(row[2]!.value.toString(), 'Ravi Stores');
    expect(double.parse(row[10]!.value.toString()), 100000); // Sale column
  });

  test('same name allowed, codes must be unique', () async {
    final tally = Get.find<TallyController>();
    final next = tally.nextCode();
    await tally.saveCustomer(
        code: next, name: 'Ravi Stores', phone: '', location: 'Salem', proofs: []);
    final ravis = tally.customers.where((c) => c.name == 'Ravi Stores').toList();
    expect(ravis.length, 2); // same name, two customers
    expect(ravis.map((c) => c.code).toSet().length, 2); // different codes
    expect(tally.isCodeTaken(next), isTrue);
    // Editing that same customer keeps their own code without a clash
    final ownId = tally.customers.firstWhere((c) => c.code == next).id;
    expect(tally.isCodeTaken(next, exceptId: ownId), isFalse);
    expect(int.parse(tally.nextCode()), int.parse(next) + 1);
  });

  test('edits and deletes are recorded with old/new values and reason', () async {
    final tally = Get.find<TallyController>();
    final cu = tally.customers.first;
    tally.saveEntry(
        customerId: cu.id, date: DateTime(2026, 11, 11), product: 'Curd',
        qty: 10, rate: 60, paid: 0);
    final e = tally.entries.last;
    final before = tally.history.length;

    // Save with no change -> nothing recorded
    tally.saveEntry(id: e.id, customerId: cu.id, date: e.date, product: 'Curd',
        qty: 10, rate: 60, paid: 0, reason: 'none');
    expect(tally.history.length, before);

    // Change qty -> recorded with old, new and reason
    tally.saveEntry(id: e.id, customerId: cu.id, date: e.date, product: 'Curd',
        qty: 8, rate: 60, paid: 0, reason: 'Customer returned 2 kg');
    final h = tally.historyOfEntry(e.id).first;
    expect(h.action, 'edited');
    expect(h.reason, 'Customer returned 2 kg');
    final qty = h.changes.firstWhere((c) => c.field == 'Qty');
    expect(qty.from, '10 kg');
    expect(qty.to, '8 kg');
    expect(tally.wasEdited(e.id), isTrue);

    // Delete -> recorded with the deleted values
    tally.deleteEntry(e.id, reason: 'Entered twice');
    final d = tally.historyOfEntry(e.id).first;
    expect(d.action, 'deleted');
    expect(d.reason, 'Entered twice');
    expect(d.changes.any((c) => c.field == 'Product' && c.from == 'Curd'), isTrue);

    // Customer edit is recorded
    await tally.saveCustomer(existing: cu, code: cu.code, name: cu.name,
        phone: '9000000000', location: cu.location, proofs: cu.proofs,
        reason: 'New number');
    expect(tally.historyOfCustomer(cu.id).first.changes.single.field, 'Phone');

    // History is part of the backup data
    expect((tally.exportData()['history'] as List).length, tally.history.length);
  });

  test('payment mode is optional, saved only with a payment', () {
    final tally = Get.find<TallyController>();
    final id = tally.customers.first.id;
    expect(tally.paymentModes, containsAll(['Cash', 'UPI', 'Bank transfer']));
    expect(tally.addPaymentMode('Cheque'), 'Cheque');
    expect(tally.addPaymentMode('cheque'), 'Cheque'); // no duplicates

    tally.saveEntry(customerId: id, date: DateTime(2026, 11, 12),
        qty: 0, rate: 0, paid: 5000, paymentMode: 'UPI');
    expect(tally.entries.last.paymentMode, 'UPI');

    tally.saveEntry(customerId: id, date: DateTime(2026, 11, 12),
        qty: 5, rate: 500, paid: 0, paymentMode: 'Cash');
    expect(tally.entries.last.paymentMode, ''); // nothing paid -> no mode

    tally.saveEntry(customerId: id, date: DateTime(2026, 11, 12),
        qty: 5, rate: 500, paid: 1000);
    expect(tally.entries.last.paymentMode, ''); // optional
  });

  test('backup after every change; empty app never overwrites backups', () async {
    final tally = Get.find<TallyController>();
    final b = Get.find<BackupService>();
    final dir = await b.backupsDir();
    final daily = File('${dir.path}/daily_${DateTime.now().toIso8601String().substring(0, 10)}.gtb');
    if (daily.existsSync()) daily.deleteSync();

    // A change -> a backup a few seconds later
    tally.saveEntry(customerId: tally.customers.first.id, date: DateTime(2026, 11, 12),
        qty: 1, rate: 500, paid: 0, product: 'Curd');
    await Future.delayed(const Duration(seconds: 5));
    expect(daily.existsSync(), isTrue);
    final goodBackup = await b.readBackup(daily.path, 'secret123');
    expect(goodBackup.entryCount, tally.entries.length);

    // App becomes empty (e.g. damaged data) -> automatic backup must NOT run
    final before = daily.lastModifiedSync();
    await tally.importData({'customers': [], 'entries': []}, {});
    expect(tally.hasData, isFalse);
    await Future.delayed(const Duration(seconds: 5));
    expect(daily.lastModifiedSync(), before);
    expect((await b.readBackup(daily.path, 'secret123')).entryCount,
        goodBackup.entryCount);

    // Restore brings the data back
    await b.restore(goodBackup, 'secret123');
    expect(tally.entries.length, goodBackup.entryCount);
  });

  test('daily file is updated in place; photos saved once, restored from proofs folder', () async {
    final tally = Get.find<TallyController>();
    final b = Get.find<BackupService>();
    final dir = await b.backupsDir();

    // A customer with a proof photo
    final photo = File('${tmp.path}/id_card.png')..writeAsBytesSync(List.filled(5000, 7));
    await tally.saveCustomer(
        code: tally.nextCode(), name: 'Proof Test', phone: '', location: '',
        proofs: [photo.path]);
    final daily = (await b.backupNow())!;
    expect(daily.path.contains('daily_'), isTrue);

    // Photo is stored once in proofs/, not inside the daily file
    final photos = Directory('${dir.path}/proofs').listSync(recursive: true)
        .whereType<File>().where((f) => f.path.endsWith('.gtp')).toList();
    expect(photos.length, 1);
    final photoTime = photos.first.lastModifiedSync();
    expect(daily.lengthSync(), lessThan(5000));

    // More changes: same daily file updated, photo NOT written again
    final dailyCount = dir.listSync().where((f) => f.path.contains('daily_')).length;
    await Future.delayed(const Duration(milliseconds: 1100));
    tally.saveEntry(customerId: tally.customers.first.id, date: DateTime(2026, 11, 12),
        qty: 2, rate: 500, paid: 0, product: 'Curd');
    await b.backupNow();
    expect(dir.listSync().where((f) => f.path.contains('daily_')).length, dailyCount);
    expect(photos.first.lastModifiedSync(), photoTime);

    // Restoring the daily file brings the photo back from proofs/
    final c = await b.readBackup(daily.path, 'secret123');
    expect(c.missingProofs, 0);
    expect(c.proofFiles.values.single.length, 5000);

    // Full backup has the photo inside
    final full = File('${tmp.path}/full.gtb')..writeAsBytesSync(await b.fullBackupBytes());
    expect(full.lengthSync(), greaterThan(daily.lengthSync()));
    expect((await b.readBackup(full.path, 'secret123')).proofFiles.length, 1);
  });

  test('state and district: saved, listed, tracked in history', () async {
    final tally = Get.find<TallyController>();
    await tally.saveCustomer(code: tally.nextCode(), name: 'Kumar Dairy', phone: '',
        location: 'Perundurai', district: ' Erode ', state: 'Tamil Nadu', proofs: []);
    final kumar = tally.customers.firstWhere((x) => x.name == 'Kumar Dairy');
    expect(kumar.district, 'Erode'); // trimmed
    expect(kumar.place, 'Perundurai, Erode, Tamil Nadu');
    expect(tally.lastState, 'Tamil Nadu'); // pre-filled for the next new customer

    await tally.saveCustomer(code: tally.nextCode(), name: 'Erode Sweets', phone: '',
        location: '', district: 'erode', state: 'Tamil Nadu', proofs: []);
    await tally.saveCustomer(code: tally.nextCode(), name: 'Kochi Mart', phone: '',
        location: '', district: 'Ernakulam', state: 'Kerala', proofs: []);

    expect(tally.statesInUse().take(2), ['Kerala', 'Tamil Nadu']);
    expect(tally.statesInUse().last, ''); // older customers without a state
    // "Erode" and "erode" are one district
    expect(tally.districtsIn('Tamil Nadu').where((d) => d.toLowerCase() == 'erode').length, 1);
    expect(tally.districtsIn('Kerala'), ['Ernakulam']);

    // Changing the state is recorded in the change history
    await tally.saveCustomer(existing: kumar, code: kumar.code, name: kumar.name,
        phone: '', location: kumar.location, district: 'Salem', state: 'Tamil Nadu',
        proofs: [], reason: 'Moved shop');
    final change = tally.historyOfCustomer(kumar.id).first.changes.single;
    expect(change.field, 'District');
    expect(change.from, 'Erode');
    expect(change.to, 'Salem');

    // Old data without state/district still loads
    final old = Customer.fromJson({'id': 'x', 'name': 'Old'});
    expect(old.state, '');
    expect(old.district, '');
    expect(old.place, '');
  });

  test('last state only changes when a state is picked', () async {
    final tally = Get.find<TallyController>();
    await tally.saveCustomer(code: tally.nextCode(), name: 'TN Shop', phone: '',
        location: '', state: 'Tamil Nadu', proofs: []);
    expect(tally.lastState, 'Tamil Nadu');

    // Editing a Kerala customer's phone only: the default stays Tamil Nadu
    final kochi = tally.customers.firstWhere((x) => x.name == 'Kochi Mart');
    await tally.saveCustomer(existing: kochi, code: kochi.code, name: kochi.name,
        phone: '9123456789', location: '', district: kochi.district,
        state: kochi.state, proofs: [], reason: 'New number');
    expect(tally.lastState, 'Tamil Nadu');

    // Moving a customer to another state does change it
    await tally.saveCustomer(existing: kochi, code: kochi.code, name: kochi.name,
        phone: kochi.phone, location: '', district: 'Mysuru', state: 'Karnataka',
        proofs: [], reason: 'Moved');
    expect(tally.lastState, 'Karnataka');
  });

  test('filtered Excel keeps history of a deleted customer from that state', () async {
    final tally = Get.find<TallyController>();
    await tally.saveCustomer(code: tally.nextCode(), name: 'Closing Shop', phone: '',
        location: '', district: 'Erode', state: 'Tamil Nadu', proofs: []);
    final shop = tally.customers.firstWhere((x) => x.name == 'Closing Shop');
    tally.deleteCustomer(shop.id, reason: 'Shop closed');

    List<String> reasons(bool Function(Customer)? filter) {
      final xl = Excel.decodeBytes(buildExcel(customerFilter: filter));
      final sheet = xl.tables['Change history']!;
      return [
        for (var i = 1; i < sheet.maxRows; i++) sheet.row(i)[7]?.value.toString() ?? ''
      ];
    }

    bool tamilNadu(Customer c) => c.state == 'Tamil Nadu';
    bool kerala(Customer c) => c.state == 'Kerala';
    expect(reasons(tamilNadu), contains('Shop closed'));
    expect(reasons(kerala), isNot(contains('Shop closed')));
    expect(reasons(null), contains('Shop closed'));
  });

  test('cash book: expenses saved, edits and deletes recorded, in backups and Excel', () {
    final tally = Get.find<TallyController>();
    expect(tally.accounts, containsAll(['Cash', 'Bank']));
    expect(tally.accountForMode('Cash'), 'Cash');
    expect(tally.accountForMode(''), 'Cash');
    expect(tally.accountForMode('UPI'), 'Bank');
    expect(tally.accountForMode('Bank transfer'), 'Bank');
    tally.setModeAccount('UPI', 'Cash');
    expect(tally.accountForMode('UPI'), 'Cash');
    tally.setModeAccount('UPI', 'Bank');

    tally.saveCashTxn(type: CashTxn.expense, date: DateTime(2026, 11, 12),
        account: 'Cash', category: 'EB (Electricity)', amount: 1850, note: 'Nov bill');
    final eb = tally.cashTxns.last;
    expect(eb.category, 'EB (Electricity)');

    // Edit: amount changed -> recorded with reason
    tally.saveCashTxn(id: eb.id, type: CashTxn.expense, date: eb.date, account: 'Cash',
        category: eb.category, amount: 1950, note: eb.note, reason: 'Late fee added');
    final h = tally.historyOfEntry(eb.id).first;
    expect(h.kind, 'cash');
    expect(h.reason, 'Late fee added');
    expect(h.changes.single.field, 'Amount');
    expect(h.changes.single.from, '₹1,850');
    expect(h.changes.single.to, '₹1,950');

    // In backups
    final data = tally.exportData();
    expect((data['cashTxns'] as List).length, tally.cashTxns.length);
    expect(data['accounts'], containsAll(['Cash', 'Bank']));

    // In Excel (only when not filtered by customer)
    final xl = Excel.decodeBytes(buildExcel());
    expect(xl.tables.keys, containsAll(['Cash book', 'Expenses & money in']));
    final filtered = Excel.decodeBytes(buildExcel(customerFilter: (c) => c.state == 'Kerala'));
    expect(filtered.tables.keys, isNot(contains('Cash book')));

    // Delete: recorded with the deleted values
    tally.deleteCashTxn(eb.id, reason: 'Entered twice');
    expect(tally.cashTxns.any((x) => x.id == eb.id), isFalse);
    final d = tally.historyOfEntry(eb.id).first;
    expect(d.action, 'deleted');
    expect(d.changes.any((c) => c.field == 'Category' && c.from == 'EB (Electricity)'), isTrue);

    // New types and accounts are kept, without duplicates
    expect(tally.addExpenseCategory('Water bill'), 'Water bill');
    expect(tally.addExpenseCategory('water BILL'), 'Water bill');
    expect(tally.addAccount('SBI current'), 'SBI current');
  });

  test('starting from the old book: opening purchases and payments', () async {
    final tally = Get.find<TallyController>();
    await tally.saveCustomer(code: tally.nextCode(), name: 'Old Book Shop', phone: '',
        location: '', proofs: [], openingBought: 50000, openingPaid: 20000,
        openingDate: DateTime(2026, 11, 1));
    final shop = tally.customers.firstWhere((x) => x.name == 'Old Book Shop');
    expect(tally.balanceOf(shop.id), 30000);
    expect(tally.percentOf(shop.id), 40);

    // New sale + payment continue from the old balance
    tally.saveEntry(customerId: shop.id, date: DateTime(2026, 11, 14), product: 'Curd',
        qty: 100, rate: 100, paid: 5000, paymentMode: 'Cash');
    expect(tally.soldOf(shop.id), 60000);
    expect(tally.paidOf(shop.id), 25000);
    expect(tally.balanceOf(shop.id), 35000);

    // Old-book money is not cash received on any day
    final moves = movementsFrom(tally.entries.where((e) => e.customerId == shop.id),
        const [], tally.accountForMode);
    expect(moves.map((m) => m.amount), [5000]);

    // Changing the old-book figures is recorded
    await tally.saveCustomer(existing: shop, code: shop.code, name: shop.name, phone: '',
        location: '', proofs: [], openingBought: 52000, openingPaid: 20000,
        openingDate: DateTime(2026, 11, 1), reason: 'Missed one bill');
    final change = tally.historyOfCustomer(shop.id).first.changes.single;
    expect(change.field, 'Old book: purchases');
    expect(change.to, '₹52,000');

    // Customers saved before this existed load with no old-book figures
    final old = Customer.fromJson({'id': 'y', 'name': 'Older'});
    expect(old.hasOpening, isFalse);
    expect(old.openingDate, isNull);
    // Saved and loaded back
    final back = Customer.fromJson(shop.toJson());
    expect(back.openingBought, 52000);
    expect(back.openingDate, DateTime(2026, 11, 1));
  });

  test('price from the formula is saved with its percent and rate', () {
    final tally = Get.find<TallyController>();
    expect(tally.priceDivisor.value, 1326);
    final id = tally.customers.first.id;
    tally.saveEntry(customerId: id, date: DateTime(2026, 11, 15), product: 'Yellow Ghee',
        qty: 10, rate: priceFromFormula(82.5, 8000, 1326), percent: 82.5, baseRate: 8000,
        paid: 0);
    final e = tally.entries.last;
    expect(e.rate, 497.74);
    expect(e.percent, 82.5);
    expect(e.baseRate, 8000);
    expect(tally.priceTypedFor('Yellow Ghee'), isFalse);

    // Saved and loaded back
    final back = Entry.fromJson(e.toJson());
    expect(back.percent, 82.5);
    expect(back.baseRate, 8000);
    // Older entries (typed price) load without percent / rate
    final old = Entry.fromJson({'id': 'o', 'customerId': id, 'date': '2026-11-01', 'rate': 500});
    expect(old.percent, isNull);

    // Changing the percent is recorded in the change history
    tally.saveEntry(id: e.id, customerId: id, date: e.date, product: 'Yellow Ghee',
        qty: 10, rate: priceFromFormula(83, 8000, 1326), percent: 83, baseRate: 8000,
        paid: 0, reason: 'Wrong percent');
    final fields = tally.historyOfEntry(e.id).first.changes.map((c) => c.field);
    expect(fields, containsAll(['Percent', 'Price/kg', 'Sale']));

    // A product priced by typing is remembered
    tally.saveEntry(customerId: id, date: DateTime(2026, 11, 15), product: 'Curd',
        qty: 5, rate: 60, paid: 0);
    expect(tally.priceTypedFor('Curd'), isTrue);
    expect(tally.entries.last.percent, isNull);

    tally.setPriceDivisor(0); // ignored
    expect(tally.priceDivisor.value, 1326);
  });

  test('"Dust White Ghee" is renamed to "Dust" in old data and old backups', () async {
    final tally = Get.find<TallyController>();
    final saved = tally.exportData(); // put everything back afterwards
    Map<String, dynamic> oldData(List<String> products) => {
          'customers': [],
          'entries': [
            Entry(id: 'r1', customerId: 'x', date: DateTime(2026, 11, 1),
                    product: 'Dust White Ghee', qty: 2, rate: 600)
                .toJson(),
            Entry(id: 'r2', customerId: 'x', date: DateTime(2026, 11, 1),
                    product: 'Curd', qty: 1, rate: 80)
                .toJson(),
          ],
          'products': products,
          'manualPriceProducts': ['Dust White Ghee'],
        };

    // Saved before the rename: list, entries and typed-price setting all renamed
    await tally.importData(oldData(['Dust White Ghee', 'Curd']), {});
    expect(tally.products, ['Dust', 'Curd']);
    expect(tally.entries.map((e) => e.product), ['Dust', 'Curd']);
    expect(tally.manualPriceProducts, {'Dust'});

    // "Dust White Ghee" added again later as its own product: left alone
    await tally.importData(oldData(['Dust', 'Curd', 'Dust White Ghee']), {});
    expect(tally.products, ['Dust', 'Curd', 'Dust White Ghee']);
    expect(tally.entries.first.product, 'Dust White Ghee');

    // New installs start with "Dust"
    expect(TallyController.defaultProducts.first, 'Dust');

    await tally.importData(saved, {});
  });
}
