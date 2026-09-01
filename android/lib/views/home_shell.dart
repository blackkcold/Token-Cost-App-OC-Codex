import 'package:flutter/material.dart';

import '../models/relay_models.dart';
import '../services/app_settings.dart';
import '../stores/dashboard_store.dart';
import 'about_view.dart';
import 'balances_view.dart';
import 'charts_view.dart';
import 'diagnostic_view.dart';
import 'overview_view.dart';
import 'pair_scanner_view.dart';
import 'settings_view.dart';

class HomeShell extends StatefulWidget {
  final DashboardStore dashboard;
  final AppSettingsStore settings;

  const HomeShell({super.key, required this.dashboard, required this.settings});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard),
      label: '总览',
    ),
    NavigationDestination(
      icon: Icon(Icons.query_stats_outlined),
      selectedIcon: Icon(Icons.query_stats),
      label: '图表',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet),
      label: '余额',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: '设置',
    ),
  ];

  Future<void> _scanAndPair() async {
    final payload = await Navigator.of(context).push<RelayPairingPayload>(
      MaterialPageRoute(builder: (_) => const PairScannerView()),
    );
    if (payload == null || !mounted) return;
    try {
      await widget.dashboard.claimPairing(payload);
    } catch (_) {
      // Store 已记录并展示安全的错误状态。
    }
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销并忘记当前手机？'),
        content: const Text(
          '只撤销当前手机终端，并清除本机保存的 App Token、端到端密钥和分析缓存；Mac 注册会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销终端'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.dashboard.revokeAndForget();
  }

  void _openDiagnostic() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DiagnosticView(relayEndpoint: widget.dashboard.relayEndpoint),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AboutView()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.dashboard, widget.settings]),
      builder: (context, _) {
        final pages = <Widget>[
          OverviewView(store: widget.dashboard),
          ChartsView(store: widget.dashboard),
          BalancesView(store: widget.dashboard),
          SettingsView(
            settings: widget.settings,
            paired: widget.dashboard.isPaired,
            onOpenDiagnostic: _openDiagnostic,
            onOpenAbout: _openAbout,
            onForgetDevice: _confirmForget,
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final content = IndexedStack(index: _index, children: pages);
            return Scaffold(
              appBar: AppBar(
                title: Text(_destinations[_index].label),
                actions: [
                  _ConnectionBadge(
                    online: widget.dashboard.pcOnline,
                    paired: widget.dashboard.isPaired,
                    checking: widget.dashboard.checkingStatus,
                    onTap: widget.dashboard.checkStatus,
                  ),
                  IconButton(
                    onPressed: _scanAndPair,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: '扫描配对',
                  ),
                  IconButton(
                    onPressed: widget.dashboard.isFetching
                        ? null
                        : widget.dashboard.refresh,
                    icon: widget.dashboard.isFetching
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: '刷新数据',
                  ),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: (value) {
                            setState(() => _index = value);
                          },
                          labelType: NavigationRailLabelType.all,
                          destinations: _destinations
                              .map(
                                (item) => NavigationRailDestination(
                                  icon: item.icon,
                                  selectedIcon: item.selectedIcon,
                                  label: Text(item.label),
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: content),
                      ],
                    )
                  : content,
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: (value) {
                        setState(() => _index = value);
                      },
                      destinations: _destinations,
                    ),
              floatingActionButton: !widget.dashboard.isPaired && _index != 3
                  ? FloatingActionButton.extended(
                      onPressed: _scanAndPair,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫描配对'),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final bool online;
  final bool paired;
  final bool checking;
  final VoidCallback onTap;

  const _ConnectionBadge({
    required this.online,
    required this.paired,
    required this.checking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = online
        ? Colors.green
        : (paired ? Colors.orange : Colors.grey);
    final label = online ? 'Mac 在线' : (paired ? 'Mac 离线' : '未配对');
    return Semantics(
      button: true,
      label: '$label，点击刷新连接状态',
      child: IconButton(
        onPressed: onTap,
        tooltip: '$label，点击刷新',
        icon: checking
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.circle, size: 12, color: color),
      ),
    );
  }
}
