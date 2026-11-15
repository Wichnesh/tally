import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/nav_controller.dart';
import 'backup_page.dart';
import 'cashbook_page.dart';
import 'customers_page.dart';
import 'daily_page.dart';
import 'dashboard_page.dart';
import 'history_page.dart';
import 'monthly_page.dart';
import 'startup_page.dart';
import 'settings_page.dart';
import 'weekly_page.dart';

/// Main window: menu on the left, selected screen on the right.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _pages = [
    DashboardPage(),
    DailyPage(),
    WeeklyPage(),
    MonthlyPage(),
    CashBookPage(),
    CustomersPage(),
    HistoryPage(),
    BackupPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavController>();
    return Scaffold(
      body: Obx(() {
        // Read here, not inside LayoutBuilder, so this Obx redraws on tab changes
        final tab = nav.tab.value;
        return Row(
          children: [
            // In a short window (e.g. the smallest size on Windows) the logo is
            // smaller so every button fits; if it still does not, the menu scrolls.
            LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: tab,
                      onDestinationSelected: (i) => nav.tab.value = i,
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(
                        padding: EdgeInsets.symmetric(vertical: box.maxHeight < 720 ? 6 : 12),
                        child: Column(
                          children: [
                            Image.asset(StartupPage.logo,
                                width: box.maxHeight < 720 ? 36 : 60,
                                height: box.maxHeight < 720 ? 36 : 60),
                            const SizedBox(height: 4),
                            const Text('Tally', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard),
                          label: Text('Dashboard'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.today_outlined),
                          selectedIcon: Icon(Icons.today),
                          label: Text('Daily'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.date_range_outlined),
                          selectedIcon: Icon(Icons.date_range),
                          label: Text('Weekly'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month),
                          label: Text('Monthly'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.account_balance_wallet_outlined),
                          selectedIcon: Icon(Icons.account_balance_wallet),
                          label: Text('Cash book'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.people_outline),
                          selectedIcon: Icon(Icons.people),
                          label: Text('Customers'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.history_outlined),
                          selectedIcon: Icon(Icons.history),
                          label: Text('History'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.backup_outlined),
                          selectedIcon: Icon(Icons.backup),
                          label: Text('Export &\nBackup', textAlign: TextAlign.center),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('Settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _pages[tab]),
          ],
        );
      }),
    );
  }
}
