import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../widgets/restore_flow.dart';
import 'home_page.dart';

/// Start screen: the Amutham logo for a moment, then the app.
/// After the app opens, it checks whether the data needs restoring.
class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  static const logo = 'assets/logo.png';
  static const showFor = Duration(milliseconds: 1800);

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(StartupPage.showFor, _openApp);
  }

  Future<void> _openApp() async {
    Get.off(() => const HomePage(),
        transition: Transition.fadeIn, duration: const Duration(milliseconds: 400));
    // If the app's data is empty or damaged but backups exist, offer a restore
    await Future.delayed(const Duration(milliseconds: 500));
    await checkForRecovery();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Opacity(
            opacity: v.clamp(0, 1),
            child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(StartupPage.logo, width: 280, height: 280),
              const SizedBox(height: 24),
              Text('Tally',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Sales · Payments · Cash book', style: t.titleMedium),
              const SizedBox(height: 32),
              const SizedBox(width: 180, child: LinearProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
