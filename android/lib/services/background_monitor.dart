import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';

import '../models/balance_snapshot.dart';
import '../models/relay_models.dart';
import 'app_settings.dart';
import 'relay_client.dart';
import 'relay_endpoint.dart';
import 'relay_identity_store.dart';
import 'relay_section_cache.dart';

const _periodicUniqueName = 'balance-monitor-periodic-refresh-v1';
const _periodicTaskName = 'balance-monitor-refresh';

class NotificationContentPolicy {
  static String text({
    required bool showSensitiveContent,
    required List<BalanceSnapshot> snapshots,
  }) {
    if (!showSensitiveContent) return '余额监控已启用，数据已安全刷新';
    final available = snapshots.where((item) => item.isAvailable).toList();
    if (available.isEmpty) return '余额监控已启用，等待 Mac 返回可用数据';
    final first = available.first;
    final provider = first.provider?.displayName ?? 'Provider';
    if (first.remainingCredits != null) {
      return '$provider · 剩余 ${first.remainingCredits!.toStringAsFixed(0)} Credits';
    }
    if (first.valueEntries.isNotEmpty) {
      final value = first.valueEntries.first;
      return '$provider · ${value.currencyCode} ${value.amount.toStringAsFixed(2)}';
    }
    if (first.usagePercent != null) {
      return '$provider · 已使用 ${(first.usagePercent! * 100).toStringAsFixed(0)}%';
    }
    return '$provider · 数据已刷新';
  }
}

class BackgroundRefreshOutcome {
  final bool success;
  final String notificationText;

  const BackgroundRefreshOutcome({
    required this.success,
    required this.notificationText,
  });
}

class BackgroundRefreshRunner {
  static Future<BackgroundRefreshOutcome> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    RelayClient? client;
    try {
      final endpoint = RelayEndpoint.requireConfigured();
      final identityStore = RelayIdentityStore(expectedServerBaseUrl: endpoint);
      final identity = await identityStore.load();
      if (identity == null) {
        return const BackgroundRefreshOutcome(
          success: true,
          notificationText: '余额监控已启用，等待安全配对',
        );
      }
      if (identity.terminalState != RelayTerminalState.active) {
        return const BackgroundRefreshOutcome(
          success: true,
          notificationText: '余额监控需要重新激活或配对',
        );
      }
      client = RelayClient(identityStore, serverBaseUrl: endpoint);
      final response = await client.query(identity);
      await RelaySectionCache().save(identity.deviceId, response);
      final settings = await AppSettingsStore.load();
      return BackgroundRefreshOutcome(
        success: true,
        notificationText: NotificationContentPolicy.text(
          showSensitiveContent: settings.showSensitiveNotificationContent,
          snapshots: response.snapshots,
        ),
      );
    } on RelayClientException catch (error) {
      return BackgroundRefreshOutcome(
        success: error.code != 'NETWORK_ERROR',
        notificationText: _safeErrorText(error.code),
      );
    } catch (_) {
      return const BackgroundRefreshOutcome(
        success: false,
        notificationText: '余额监控暂时无法刷新，请打开 App 检查',
      );
    } finally {
      client?.dispose();
    }
  }

  static String _safeErrorText(String? code) => switch (code) {
    'PC_DISCONNECTED' ||
    'PC_OFFLINE' ||
    'PC_SEND_FAILED' ||
    'PC_RESPONSE_TIMEOUT' => 'Mac 当前离线或响应超时',
    'TERMINAL_EXPIRED' ||
    'TERMINAL_REVOKED' ||
    'TERMINAL_NOT_ACTIVE' => '终端需要重新配对',
    _ => '余额监控刷新失败，请打开 App 检查',
  };
}

@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _periodicTaskName) return true;
    final outcome = await BackgroundRefreshRunner.run();
    return outcome.success;
  });
}

@pragma('vm:entry-point')
void foregroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_BalanceMonitorTaskHandler());
}

class _BalanceMonitorTaskHandler extends TaskHandler {
  bool _refreshing = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _refresh();

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final outcome = await BackgroundRefreshRunner.run();
      await FlutterForegroundTask.updateService(
        notificationText: outcome.notificationText,
      );
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}

class BackgroundMonitorCoordinator {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    await Workmanager().initialize(backgroundCallbackDispatcher);
    _initialized = true;
  }

  static Future<void> apply(AppSettingsStore settings) async {
    if (!_initialized) await initialize();
    await Workmanager().cancelByUniqueName(_periodicUniqueName);
    if (settings.backgroundRefreshEnabled) {
      await Workmanager().registerPeriodicTask(
        _periodicUniqueName,
        _periodicTaskName,
        frequency: Duration(minutes: settings.refreshMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'balance_monitor_status',
        channelName: '余额监控状态',
        channelDescription: '显示用户主动启用的余额监控运行状态',
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        showBadge: false,
        visibility: settings.hideSensitiveContentOnLockScreen
            ? NotificationVisibility.VISIBILITY_PRIVATE
            : NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          settings.refreshMinutes * 60 * 1000,
        ),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
        allowAutoRestart: false,
      ),
    );

    final running = await FlutterForegroundTask.isRunningService;
    if (!settings.realtimeMonitorEnabled) {
      if (running) await FlutterForegroundTask.stopService();
      return;
    }

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    final granted = permission == NotificationPermission.granted
        ? permission
        : await FlutterForegroundTask.requestNotificationPermission();
    if (granted != NotificationPermission.granted) {
      throw StateError('通知权限未授予，实时常驻监控未启动');
    }
    if (running) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: '余额监控',
        notificationText: '正在建立安全刷新链路',
        callback: foregroundStartCallback,
      );
    }
  }
}
