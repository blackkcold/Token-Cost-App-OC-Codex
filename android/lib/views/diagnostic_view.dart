import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diagnostic_log.dart';
import '../services/relay_identity_store.dart';

/// 开发者诊断面板：展示设备/服务器信息与内存环形日志，便于排查"已配对但 Mac 当前离线"等问题。
class DiagnosticView extends StatefulWidget {
  final Uri relayEndpoint;

  const DiagnosticView({super.key, required this.relayEndpoint});

  @override
  State<DiagnosticView> createState() => _DiagnosticViewState();
}

class _DiagnosticViewState extends State<DiagnosticView> {
  late final RelayIdentityStore _store;
  String _deviceId = '—';
  String _server = '—';
  DiagnosticCategory _filter = DiagnosticCategory.connection;

  @override
  void initState() {
    super.initState();
    _store = RelayIdentityStore(expectedServerBaseUrl: widget.relayEndpoint);
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final identity = await _store.load();
    if (!mounted) return;
    setState(() {
      _deviceId = identity?.deviceId ?? '—';
      _server = identity == null ? '—' : '已配置';
    });
  }

  Future<void> _copyLog() async {
    final text = DiagnosticLog.instance.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('诊断日志已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者诊断'),
        actions: [
          IconButton(
            onPressed: _copyLog,
            icon: const Icon(Icons.copy_all),
            tooltip: '复制全部日志',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '诊断日志（${DiagnosticLog.instance.length} 条）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextButton(
                  onPressed: () {
                    DiagnosticLog.instance.clear();
                    setState(() {});
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in DiagnosticCategory.values)
                  _categoryChip(category),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _LogList(
              filter: _filter,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(DiagnosticCategory category) {
    final selected = _filter == category;
    final count = DiagnosticLog.instance.byCategory(category).length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('${category.label} $count'),
        selected: selected,
        onSelected: (_) => setState(() => _filter = category),
      ),
    );
  }

  Widget _infoCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备与服务器信息', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            _infoRow('设备 ID', _deviceId),
            const SizedBox(height: 6),
            _infoRow('服务器', _server),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _LogList extends StatefulWidget {
  final VoidCallback onChanged;
  final DiagnosticCategory filter;

  const _LogList({required this.onChanged, required this.filter});

  @override
  State<_LogList> createState() => _LogListState();
}

class _LogListState extends State<_LogList> {
  VoidCallback? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = DiagnosticLog.instance.listen((_) => widget.onChanged());
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = DiagnosticLog.instance.byCategory(widget.filter);
    if (entries.isEmpty) {
      return const Center(child: Text('暂无该分类诊断日志'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, index) {
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '${entry.timestamp.toLocal().toString()}  [${entry.category.label}] ${entry.message}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}
