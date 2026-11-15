import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'controllers/dashboard_controller.dart';
import 'controllers/nav_controller.dart';
import 'controllers/tally_controller.dart';
import 'pages/startup_page.dart';
import 'services/app_data.dart';
import 'services/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local data file
  if (Platform.isWindows) {
    // In the app's own AppData folder, not Documents (see appDataDir)
    final dir = (await appDataDir()).path;
    try {
      await copyOldWindowsData(
          from: (await getApplicationDocumentsDirectory()).path, to: dir);
    } catch (_) {} // the old data stays in Documents and can be restored by hand
    await GetStorage('GetStorage', dir).initStorage;
  } else {
    await GetStorage.init(); // macOS: the app's own Documents folder
  }
  Get.put(TallyController());
  Get.put(NavController());
  Get.put(DashboardController()); // dashboard filters
  Get.put(BackupService()); // encrypted backup after every change
  runApp(const GheeTallyApp());
}

class GheeTallyApp extends StatelessWidget {
  const GheeTallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Tally',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE0A100), // ghee gold
        useMaterial3: true,
      ),
      // Amutham logo first; it then opens the app and checks the data
      home: const StartupPage(),
    );
  }
}
