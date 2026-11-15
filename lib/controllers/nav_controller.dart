import 'package:get/get.dart';

import '../utils.dart';
import 'customer_filter.dart';

/// Screen numbers for the left menu.
class Tabs {
  static const dashboard = 0;
  static const daily = 1;
  static const weekly = 2;
  static const monthly = 3;
  static const cashbook = 4;
  static const customers = 5;
  static const history = 6;
  static const backup = 7;
  static const settings = 8;
}

/// Which screen is open, and which day / week / month the calendars show.
class NavController extends GetxController {
  final tab = Tabs.dashboard.obs;
  final day = dateOnly(DateTime.now()).obs;
  final weekStart = weekStartOf(DateTime.now()).obs;
  final month = DateTime(DateTime.now().year, DateTime.now().month).obs;
  final weekAsTable = false.obs; // Weekly screen: calendar or table

  /// Daily / Weekly / Monthly show the cash book instead of sales
  /// ("Sales | Cash book" switch). Shared, so it stays when moving between them.
  final calendarCash = false.obs;

  /// Customer / state / district filter shared by Daily, Weekly and Monthly,
  /// so it stays the same when moving between them.
  final calendarFilter = CustomerFilter();

  /// State / district filter on the Customers screen.
  final customersFilter = CustomerFilter();

  // Cash book screen: one day, or a whole month
  final cashDay = dateOnly(DateTime.now()).obs;
  final cashMonth = DateTime(DateTime.now().year, DateTime.now().month).obs;
  final cashMonthView = false.obs;

  void openCashDay(DateTime d) {
    cashDay.value = dateOnly(d);
    cashMonthView.value = false;
    tab.value = Tabs.cashbook;
  }

  void openDay(DateTime d) {
    day.value = dateOnly(d);
    tab.value = Tabs.daily;
  }
}
