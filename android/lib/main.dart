import 'package:flutter/material.dart';

import 'services/background_monitor.dart';
import 'services/relay_endpoint.dart';
import 'views/dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundMonitorCoordinator.initialize();
  runApp(BalanceMonitorApp(relayEndpoint: RelayEndpoint.requireConfigured()));
}

class BalanceMonitorApp extends StatelessWidget {
  final Uri relayEndpoint;

  const BalanceMonitorApp({super.key, required this.relayEndpoint});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '余额监控',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: DashboardView(relayEndpoint: relayEndpoint),
    );
  }
}
