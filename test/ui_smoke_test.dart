// Opens every screen and dialog with sample data at the smallest window size
// the app allows (1100 x 720) and at a common laptop size, and fails on any
// layout error (overflow, exceptions).
//
// Screenshots: run with SHOT_DIR=/some/folder to save a PNG of each screen.
//   SHOT_DIR=/tmp/shots fvm flutter test test/ui_smoke_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:ghee_tally/controllers/dashboard_controller.dart';
import 'package:ghee_tally/controllers/nav_controller.dart';
import 'package:ghee_tally/controllers/tally_controller.dart';
import 'package:ghee_tally/models.dart';
import 'package:ghee_tally/pages/customer_detail_page.dart';
import 'package:ghee_tally/pages/home_page.dart';
import 'package:ghee_tally/pages/startup_page.dart';
import 'package:ghee_tally/services/backup_service.dart';
import 'package:ghee_tally/utils.dart';
import 'package:ghee_tally/widgets/cash_dialog.dart';
import 'package:ghee_tally/widgets/cash_views.dart';
import 'package:ghee_tally/widgets/customer_dialog.dart';
import 'package:ghee_tally/widgets/customer_filter_bar.dart';
import 'package:ghee_tally/widgets/entry_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String dir;
  _FakePaths(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir; // Windows: appDataDir
}

/// Backup service without timers or file access (not needed to draw screens).
class _QuietBackups extends BackupService {
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> refreshList() async {}
}

final _shotKey = GlobalKey();

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/fvm/versions/3.41.4';
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$fonts/$f');
      if (file.existsSync()) {
        loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      }
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void _seed(TallyController c) {
  final today = DateTime.now();
  DateTime day(int ago) => DateTime(today.year, today.month, today.day - ago);
  final customers = [
    Customer(id: 'c1', code: '1001', name: 'Ravi Stores', phone: '9876543210',
        location: 'Perundurai', district: 'Erode', state: 'Tamil Nadu',
        openingBought: 185000, openingPaid: 140000, openingDate: day(40)),
    Customer(id: 'c2', code: '1002', name: 'Ravi Stores', phone: '9000000001',
        location: 'Attur', district: 'Salem', state: 'Tamil Nadu'),
    Customer(id: 'c3', code: '1003',
        name: 'Sri Lakshmi Narasimha Ghee and Dairy Products Wholesale Traders',
        location: 'Gandhipuram', district: 'Coimbatore', state: 'Tamil Nadu'),
    Customer(id: 'c4', code: '1004', name: 'Kochi Mart',
        district: 'Ernakulam', state: 'Kerala'),
    Customer(id: 'c5', code: '1005', name: 'Mysore Sweets',
        district: 'Mysuru', state: 'Karnataka'),
    Customer(id: 'c6', code: '1006', name: 'Old Customer'), // no state
    Customer(id: 'c7', code: '1007', name: 'Delta Traders',
        district: 'Nicobar', state: 'Dadra and Nagar Haveli and Daman and Diu'),
  ];
  const products = [
    'Dust', 'Yellow Ghee', 'White Butter', 'Yellow Butter', 'Curd', 'Buttermilk',
  ];
  const modes = ['Cash', 'UPI', 'Bank transfer', ''];
  final entries = <Entry>[];
  var n = 0;
  for (var ago = 0; ago < 35; ago++) {
    for (final cu in customers) {
      if ((ago + cu.id.hashCode) % 3 != 0) continue;
      n++;
      entries.add(Entry(
        id: 'e$n',
        customerId: cu.id,
        date: day(ago),
        product: products[n % products.length],
        qty: 5.0 + (n % 40),
        rate: 480.0 + (n % 5) * 10,
        paid: n % 4 == 0 ? 0 : 10000.0 + (n % 7) * 2500,
        paymentMode: modes[n % modes.length],
        note: n % 9 == 0 ? 'Delivered by van, paid part at shop' : '',
      ));
    }
  }
  c.customers.assignAll(customers);
  c.entries.assignAll(entries);

  // Cash book: opening balances, daily expenses, money in, a transfer
  const kinds = ['EB (Electricity)', 'Tea / Snacks', 'Transport / Diesel', 'Salary / Wages'];
  final txns = <CashTxn>[
    CashTxn(id: 'o1', type: CashTxn.opening, date: day(20), account: 'Cash', amount: 25000),
    CashTxn(id: 'o2', type: CashTxn.opening, date: day(20), account: 'Bank', amount: 150000),
    CashTxn(id: 'o3', type: CashTxn.opening, date: day(0), account: 'Cash', amount: 50000,
        note: 'Counted at 9 am'),
    CashTxn(id: 'i1', type: CashTxn.income, date: day(0), account: 'Cash', amount: 20000,
        category: 'Owner added money'),
    CashTxn(id: 't1', type: CashTxn.transfer, date: day(0), account: 'Cash',
        toAccount: 'Bank', amount: 30000, note: 'Deposited at SBI'),
  ];
  for (var ago = 0; ago < 20; ago++) {
    txns.add(CashTxn(
      id: 'x$ago',
      type: CashTxn.expense,
      date: day(ago),
      account: ago.isEven ? 'Cash' : 'Bank',
      category: kinds[ago % kinds.length],
      amount: 300.0 + ago * 150,
      note: ago == 0 ? 'Monthly bill, paid at the EB office' : '',
    ));
  }
  c.cashTxns.assignAll(txns);
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHOT_DIR'];
  if (dir == null) return;
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('ghee_tally_ui');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    BackupService.dirOverride = '${tmp.path}/backups';
    await GetStorage.init();
    await _loadFonts();
  });

  // On Windows the app's data file is still open here and cannot be deleted;
  // the system cleans Temp later.
  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  // 1100x720: the smallest window. 1084x680: the content area left inside a
  // 1100x720 window on Windows (title bar and borders) and on macOS (1100x692).
  for (final size in const [Size(1100, 720), Size(1084, 680), Size(1440, 900)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('all screens draw without layout errors at $tag', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Get.reset();
      final c = Get.put(TallyController());
      final nav = Get.put(NavController());
      final dash = Get.put(DashboardController());
      Get.put<BackupService>(_QuietBackups());
      _seed(c);

      await tester.pumpWidget(GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFFE0A100), useMaterial3: true),
        builder: (context, child) => RepaintBoundary(key: _shotKey, child: child!),
        home: const HomePage(),
      ));
      await _settle(tester);

      Future<void> check(String name) async {
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '$name at $tag');
        await _shot(tester, '$tag-$name');
      }

      // ----- Every screen in the menu -----
      const tabs = {
        Tabs.dashboard: '01-dashboard',
        Tabs.daily: '02-daily',
        Tabs.weekly: '03-weekly',
        Tabs.monthly: '05-monthly',
        Tabs.cashbook: '05b-cashbook-day',
        Tabs.customers: '06-customers',
        Tabs.history: '07-history',
        Tabs.backup: '08-backup',
        Tabs.settings: '09-settings',
      };
      for (final t in tabs.entries) {
        nav.tab.value = t.key;
        await check(t.value);
      }
      nav.tab.value = Tabs.cashbook;
      nav.cashMonthView.value = true;
      await check('05c-cashbook-month');
      nav.cashMonthView.value = false;

      nav.tab.value = Tabs.weekly;
      nav.weekAsTable.value = true;
      await check('04-weekly-table');
      nav.weekAsTable.value = false;

      // A week with long dates still fits next to both switches
      nav.weekStart.value = DateTime(2026, 5, 18);
      await check('03c-weekly-long-dates');
      nav.weekStart.value = weekStartOf(DateTime.now());

      // ----- "Sales | Cash book" switch on Daily, Weekly and Monthly -----
      Finder switchTo(String label) => find.descendant(
          of: find.byType(SalesCashSwitch), matching: find.text(label));
      nav.tab.value = Tabs.daily;
      await _settle(tester);
      await tester.tap(switchTo('Cash book'));
      await check('02b-daily-cashbook');
      expect(nav.calendarCash.value, isTrue);
      expect(find.text('Add expense'), findsOneWidget);
      expect(find.text('Add entry'), findsNothing); // "Add sale entry" is in the cash buttons
      expect(find.byType(CustomerFilterBar), findsNothing); // cash book is shop-wide

      // The choice stays when moving to Weekly and Monthly
      nav.tab.value = Tabs.weekly;
      await check('03b-weekly-cashbook');
      expect(find.text('Add expense'), findsOneWidget);
      expect(find.text('Calendar'), findsNothing); // Calendar / Table is for sales only
      expect(find.text('Expenses by type'), findsOneWidget);

      nav.tab.value = Tabs.monthly;
      await check('05d-monthly-cashbook');
      expect(find.text('Expenses by type'), findsOneWidget);

      // Clicking a day in the month's cash book opens that day's cash book in Daily
      final today = dateOnly(DateTime.now());
      final todayRow = find.text(DateFormat('EEE, d MMM').format(today));
      // Scroll down until the row is built (small windows), then fully into view
      await tester.scrollUntilVisible(todayRow, 300,
          scrollable: find
              .descendant(of: find.byType(CashPeriodView), matching: find.byType(Scrollable))
              .first);
      await tester.ensureVisible(todayRow);
      await _settle(tester);
      await tester.tap(todayRow);
      await _settle(tester);
      expect(nav.tab.value, Tabs.daily);
      expect(nav.day.value, today);
      expect(find.byType(CashDayView), findsOneWidget);

      // Back to sales
      await tester.tap(switchTo('Sales'));
      await _settle(tester);
      expect(nav.calendarCash.value, isFalse);
      expect(find.text('Add entry'), findsOneWidget);
      expect(find.byType(CustomerFilterBar), findsOneWidget);

      // ----- Filters switched on -----
      dash.customers.state.value = 'Tamil Nadu';
      dash.customers.district.value = 'Erode';
      nav.tab.value = Tabs.dashboard;
      await check('10-dashboard-filtered');

      nav.calendarFilter.state.value = 'Tamil Nadu';
      nav.tab.value = Tabs.monthly;
      await check('11-monthly-filtered');

      nav.customersFilter.state.value = 'Kerala';
      nav.tab.value = Tabs.customers;
      await check('12-customers-filtered');

      // A filter whose value no customer has any more must not crash
      nav.customersFilter.state.value = 'Goa';
      nav.customersFilter.district.value = 'Panaji';
      await check('13-customers-filter-unused-value');
      nav.customersFilter.reset();

      // ----- Customer page and dialogs -----
      Get.to(() => CustomerDetailPage(customerId: 'c3'));
      await check('14-customer-detail');
      Get.back();
      await _settle(tester);

      openCustomerDialog(c.customerById('c7'));
      await check('15-customer-dialog-edit');
      Get.back();
      await _settle(tester);

      Get.to(() => CustomerDetailPage(customerId: 'c1'));
      await check('15b-customer-detail-old-book');
      expect(find.text('Opening (old book)'), findsOneWidget);
      Get.back();
      await _settle(tester);
      openCustomerDialog(c.customerById('c1'));
      await check('15c-customer-dialog-old-book');
      expect(find.text('Balance due from old book: ₹45,000'), findsOneWidget);
      Get.back();
      await _settle(tester);

      openCustomerDialog();
      await check('16-customer-dialog-new');
      Get.back();
      await _settle(tester);

      nav.tab.value = Tabs.cashbook;
      openCashDialog(CashTxn.expense);
      await check('17b-expense-dialog');
      Get.back();
      await _settle(tester);
      openCashDialog(CashTxn.opening, account: 'Cash');
      await check('17c-opening-dialog');
      Get.back();
      await _settle(tester);
      openCashDialog(CashTxn.transfer);
      await check('17d-transfer-dialog');
      Get.back();
      await _settle(tester);

      // Money in from a customer: pick customer, amount, UPI, Save
      openCashDialog(CashTxn.income);
      await check('17e-money-in-customer');
      await tester.tap(find.text('Customer *'));
      await _settle(tester);
      await tester.enterText(
          find.descendant(
              of: find.widgetWithText(AlertDialog, 'Choose customer'),
              matching: find.byType(TextField)),
          '#1004');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.textContaining('Balance due:'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Amount received (₹) *'), '5000');
      await tester.tap(find.text('Cash').last); // payment mode dropdown
      await _settle(tester);
      await tester.tap(find.text('UPI').last);
      await _settle(tester);
      expect(find.textContaining('Goes to: Bank'), findsOneWidget);
      await check('17f-money-in-customer-filled');
      final before = c.entries.length;
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(c.entries.length, before + 1);
      final paid = c.entries.last;
      expect(paid.customerId, 'c4');
      expect(paid.paid, 5000);
      expect(paid.qty, 0);
      expect(paid.paymentMode, 'UPI');
      expect(c.accountForMode(paid.paymentMode), 'Bank');
      await tester.pump(const Duration(seconds: 4)); // let the "saved" message close
      await _settle(tester);

      // Money in -> "Sale entry" switches to the full entry form
      openCashDialog(CashTxn.income);
      await _settle(tester);
      await tester.tap(find.text('Sale entry'));
      await _settle(tester);
      expect(find.text('New entry'), findsOneWidget);
      expect(find.text('Quantity (kg)'), findsOneWidget);
      expect(find.text('Percent (%)'), findsOneWidget); // price from the formula
      expect(find.text('Rate (₹)'), findsOneWidget);
      expect(find.text('New money in'), findsNothing);
      await check('17g-money-in-sale-entry');
      Get.back();
      await _settle(tester);

      openEntryDialog(customerId: 'c1');
      await check('17-entry-dialog');
      // Price per kg from the formula: 82.5 × ₹8,000 ÷ 1326 = ₹497.74
      await tester.enterText(find.widgetWithText(TextFormField, 'Quantity (kg)'), '10');
      await tester.enterText(find.widgetWithText(TextFormField, 'Percent (%)'), '82.5');
      await tester.enterText(find.widgetWithText(TextFormField, 'Rate (₹)'), '8000');
      await _settle(tester);
      expect(find.text('Price per kg = 82.5 × ₹8,000 ÷ 1326 = ₹497.74'), findsOneWidget);
      expect(find.text('Sale amount: ₹4,977.40'), findsOneWidget);
      await check('17h-entry-formula');
      // Switch to typing the price: it starts from the worked-out price
      await tester.tap(find.text('Type price per kg instead'));
      await _settle(tester);
      expect(find.widgetWithText(TextFormField, 'Price per kg (₹)'), findsOneWidget);
      expect(find.text('497.74'), findsOneWidget);
      await tester.tap(find.textContaining('Use the formula'));
      await _settle(tester);
      // Product, then save
      await tester.tap(find.text('Product'));
      await _settle(tester);
      await tester.tap(find.text('Yellow Ghee').last);
      await _settle(tester);
      final countBefore = c.entries.length;
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(c.entries.length, countBefore + 1);
      final saved = c.entries.last;
      expect(saved.percent, 82.5);
      expect(saved.baseRate, 8000);
      expect(saved.rate, 497.74);
      expect(saved.amount, closeTo(4977.4, 0.001));
      await _settle(tester);

      // ----- Customer search window: type, press Enter, check the choice -----
      dash.reset();
      nav.tab.value = Tabs.dashboard;
      await _settle(tester);
      await tester.tap(find.text('All customers').first);
      await check('18-customer-search');
      final searchBox = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(searchBox, 'ravi erode');
      await check('19-customer-search-typed');
      expect(find.text('1 customer · Enter picks the first'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
      await _settle(tester);
      expect(dash.customers.customerId.value, 'c1'); // the Erode Ravi, not Salem
      expect(find.text('Ravi Stores · #1001 — Perundurai, Erode, Tamil Nadu'), findsOneWidget);
      await check('20-dashboard-one-customer');

      // Editing that customer updates the text in the box (no stale label)
      final ravi = c.customerById('c1')!;
      ravi.district = 'Salem';
      c.customers.refresh();
      await _settle(tester);
      expect(find.text('Ravi Stores · #1001 — Perundurai, Salem, Tamil Nadu'), findsOneWidget);
      ravi.district = 'Erode';
      c.customers.refresh();

      // Choosing another state drops a customer who is not in it
      dash.customers.setState('Kerala', c.districtsIn, customerById: c.customerById);
      await _settle(tester);
      expect(dash.customers.customerId.value, isNull);
      dash.reset();

      // ----- Entry form: pick a customer by typing their code -----
      openEntryDialog();
      await _settle(tester);
      await tester.tap(find.text('Customer *'));
      await _settle(tester);
      await tester.enterText(
          find.descendant(
              of: find.widgetWithText(AlertDialog, 'Choose customer'),
              matching: find.byType(TextField)),
          '#1004');
      await _settle(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await check('21-entry-dialog-picked');
      expect(find.text('Kochi Mart · #1004 — Ernakulam, Kerala'), findsOneWidget);
      Get.back();
      await _settle(tester);

      expect(tester.takeException(), isNull);
      Get.reset();
    });
  }

  testWidgets('start screen shows the logo, then opens the app', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Get.reset();
    final c = Get.put(TallyController());
    Get.put(NavController());
    Get.put(DashboardController());
    Get.put<BackupService>(_QuietBackups());
    _seed(c);

    await tester.pumpWidget(GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFE0A100), useMaterial3: true),
      builder: (context, child) => RepaintBoundary(key: _shotKey, child: child!),
      home: const StartupPage(),
    ));
    // Load the logo picture so it shows in the screenshot
    await tester.runAsync(() async {
      await precacheImage(
          const AssetImage(StartupPage.logo), tester.element(find.byType(StartupPage)));
    });
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.image(const AssetImage(StartupPage.logo)), findsOneWidget);
    expect(find.text('Tally'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, '00-start-screen');

    // After a moment the app opens on its own
    await tester.pump(StartupPage.showFor);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1)); // the data check after opening
    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(StartupPage), findsNothing);
    expect(find.image(const AssetImage(StartupPage.logo)), findsOneWidget); // in the menu
    expect(tester.takeException(), isNull);
    await _shot(tester, '00b-after-start');
    Get.reset();
  });
}
