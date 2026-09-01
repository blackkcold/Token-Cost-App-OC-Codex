import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/background_monitor.dart';
import '../services/diagnostic_log.dart';
import '../stores/dashboard_store.dart';
import 'home_shell.dart';

export '../stores/dashboard_store.dart'
    show statusMessageAfterOnlineCheck, terminalStateMessage;

class DashboardView extends StatefulWidget {
  final Uri relayEndpoint;

  const DashboardView({super.key, required this.relayEndpoint});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final DashboardStore _dashboard;
  AppSettingsStore? _settings;
  bool _syncingRuntimeSettings = false;

  @override
  void initState() {
    super.initState();
    _dashboard = DashboardStore(relayEndpoint: widget.relayEndpoint);
    _initialize();
  }

  Future<void> _initialize() async {
    final settings = await AppSettingsStore.load();
    await DiagnosticLog.instance.configurePersistence(
      settings.persistDiagnostics,
    );
    settings.addListener(_syncRuntimeSettings);
    await _applyRuntimeSettings(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
    await _dashboard.initialize();
  }

  void _syncRuntimeSettings() {
    final settings = _settings;
    if (settings == null || _syncingRuntimeSettings) return;
    unawaited(_applyRuntimeSettings(settings));
  }

  Future<void> _applyRuntimeSettings(AppSettingsStore settings) async {
    _syncingRuntimeSettings = true;
    try {
      await DiagnosticLog.instance.configurePersistence(
        settings.persistDiagnostics,
      );
      await BackgroundMonitorCoordinator.apply(settings);
    } catch (error) {
      DiagnosticLog.instance.record(
        '[background] 配置未生效：$error',
        category: DiagnosticCategory.connection,
      );
      if (settings.realtimeMonitorEnabled) {
        await settings.setRealtimeMonitorEnabled(false);
      }
    } finally {
      _syncingRuntimeSettings = false;
    }
  }

  @override
  void dispose() {
    _settings?.removeListener(_syncRuntimeSettings);
    _settings?.dispose();
    _dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeShell(dashboard: _dashboard, settings: settings);
  }
}
