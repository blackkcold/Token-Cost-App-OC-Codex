import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/diagnostic_log.dart';

class SettingsView extends StatelessWidget {
  final AppSettingsStore settings;
  final bool paired;
  final VoidCallback onOpenDiagnostic;
  final VoidCallback onOpenAbout;
  final VoidCallback onForgetDevice;

  const SettingsView({
    super.key,
    required this.settings,
    required this.paired,
    required this.onOpenDiagnostic,
    required this.onOpenAbout,
    required this.onForgetDevice,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        const _SectionTitle('后台监控'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.backgroundRefreshEnabled,
                onChanged: settings.setBackgroundRefreshEnabled,
                secondary: const Icon(Icons.schedule_outlined),
                title: const Text('系统周期刷新'),
                subtitle: const Text('非精确定时，系统可延迟；最短 15 分钟'),
              ),
              SwitchListTile(
                value: settings.realtimeMonitorEnabled,
                onChanged: settings.setRealtimeMonitorEnabled,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('实时常驻监控'),
                subtitle: const Text('用户主动开启的前台服务；Android 15 不保证永久运行'),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('刷新间隔'),
                trailing: DropdownButton<int>(
                  value: settings.refreshMinutes,
                  onChanged: (value) {
                    if (value != null) settings.setRefreshMinutes(value);
                  },
                  items: [
                    for (final value in AppSettingsStore.allowedRefreshMinutes)
                      DropdownMenuItem(value: value, child: Text('$value 分钟')),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _SectionTitle('通知隐私'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.showSensitiveNotificationContent,
                onChanged: settings.setShowSensitiveNotificationContent,
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('通知显示余额/配额'),
                subtitle: const Text('默认关闭；开启后通知可能暴露账户信息'),
              ),
              SwitchListTile(
                value: settings.hideSensitiveContentOnLockScreen,
                onChanged: settings.setHideSensitiveContentOnLockScreen,
                secondary: const Icon(Icons.lock_outline),
                title: const Text('锁屏隐藏敏感内容'),
              ),
            ],
          ),
        ),
        const _SectionTitle('开发者模式'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.developerModeEnabled,
                onChanged: settings.setDeveloperModeEnabled,
                secondary: const Icon(Icons.developer_mode_outlined),
                title: const Text('启用开发者诊断'),
              ),
              SwitchListTile(
                value: settings.persistDiagnostics,
                onChanged: (value) async {
                  await settings.setPersistDiagnostics(value);
                  await DiagnosticLog.instance.configurePersistence(value);
                },
                secondary: const Icon(Icons.description_outlined),
                title: const Text('诊断日志落盘'),
                subtitle: const Text('最多 1 MiB，写入前自动脱敏；默认关闭'),
              ),
              if (settings.developerModeEnabled)
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('打开诊断面板'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenDiagnostic,
                ),
            ],
          ),
        ),
        const _SectionTitle('设备与应用'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于与隐私'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenAbout,
              ),
              ListTile(
                enabled: paired,
                leading: Icon(
                  Icons.phonelink_erase_outlined,
                  color: paired ? Theme.of(context).colorScheme.error : null,
                ),
                title: const Text('撤销并忘记当前手机'),
                subtitle: const Text('网络撤销失败时保留凭据，便于安全重试'),
                onTap: paired ? onForgetDevice : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
