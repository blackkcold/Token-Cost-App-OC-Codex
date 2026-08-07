import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/balance_snapshot.dart';
import '../models/relay_models.dart';
import '../services/diagnostic_log.dart';
import '../services/relay_client.dart';
import '../services/relay_identity_store.dart';
import 'balance_card.dart';
import 'diagnostic_view.dart';
import 'pair_scanner_view.dart';

const _offlineStatusMessage = '已配对，但 Mac 当前离线';
const _reconnectedStatusMessage = 'Mac 已重新连接，请再次刷新余额';
const _queryRecoveredStatusMessage = 'Mac 已连接，但上次查询超时，请再次刷新余额';

@visibleForTesting
String? statusMessageAfterOnlineCheck({
  required bool online,
  required String? currentMessage,
}) {
  if (!online) return currentMessage ?? _offlineStatusMessage;
  if (currentMessage == null ||
      currentMessage == _offlineStatusMessage ||
      currentMessage.startsWith('连接检查失败：')) {
    return null;
  }
  if (currentMessage.contains('Mac 连接已断开')) return _reconnectedStatusMessage;
  if (currentMessage.contains('Mac 响应超时')) return _queryRecoveredStatusMessage;
  return currentMessage;
}

class DashboardView extends StatefulWidget {
  final Uri relayEndpoint;

  const DashboardView({super.key, required this.relayEndpoint});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final RelayIdentityStore _store;
  late final RelayClient _client;
  RelayIdentity? _identity;
  List<BalanceSnapshot> _snapshots = const [];
  bool _loading = true;
  bool _isFetching = false;
  bool _pcOnline = false;
  bool _checkingStatus = false;
  Timer? _statusTimer;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _store = RelayIdentityStore(expectedServerBaseUrl: widget.relayEndpoint);
    _client = RelayClient(_store, serverBaseUrl: widget.relayEndpoint);
    _initialize();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final identity = await _store.load();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _loading = false;
      _statusMessage = identity == null ? '请扫描 Mac 端生成的安全配对二维码' : null;
    });
    if (identity != null) {
      DiagnosticLog.instance.record(
        '[init] 已加载配对身份 device=${_shortId(identity.deviceId)}',
        category: DiagnosticCategory.connection,
      );
      await _checkRegistration(identity);
      if (_identity != null) {
        await _checkStatus();
        _startStatusPolling();
        // 启动即自动抓取一次余额，避免停留在"没有可显示的数据"空态。
        await _refresh();
      }
    } else {
      DiagnosticLog.instance.record(
        '[init] 未找到本地配对身份',
        category: DiagnosticCategory.connection,
      );
    }
  }

  static String _shortId(String deviceId) =>
      deviceId.length <= 8 ? deviceId : '${deviceId.substring(0, 8)}…';

  /// 周期性复查 PC 在线状态，使连接徽章与中继服务器实时一致。
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStatus(),
    );
  }

  /// 注册状态检测：设备若已在 Mac 端删除（404），清本地并提示重新配对。
  Future<void> _checkRegistration(RelayIdentity identity) async {
    try {
      final registered = await _client.registrationStatus(identity);
      if (registered == null) {
        await _store.delete();
        if (!mounted) return;
        setState(() {
          _identity = null;
          _snapshots = const [];
          _pcOnline = false;
          _statusMessage = '设备已在 Mac 端删除，请重新扫描配对二维码';
        });
        DiagnosticLog.instance.record(
          '[registration] 设备已在 Mac 端删除，清空本地配对',
          category: DiagnosticCategory.registration,
        );
      }
    } catch (_) {
      // 网络失败不阻塞，保持当前状态。
    }
  }

  Future<void> _checkStatus() async {
    final identity = _identity;
    // 连接状态检查独立于内容抓取：始终允许刷新连接状态，不被内容加载冻结。
    if (identity == null || _checkingStatus) return;
    _checkingStatus = true;
    try {
      final online = await _client.online(identity);
      if (!mounted) return;
      setState(() {
        _pcOnline = online;
        _statusMessage = statusMessageAfterOnlineCheck(
          online: online,
          currentMessage: _statusMessage,
        );
      });
      DiagnosticLog.instance.record(
        '[online] 连接状态检查完成 online=$online',
        category: DiagnosticCategory.connection,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pcOnline = false;
        _statusMessage = '连接检查失败：$error';
      });
      DiagnosticLog.instance.record(
        '[online] 连接检查失败：$error',
        category: DiagnosticCategory.connection,
      );
    } finally {
      _checkingStatus = false;
    }
  }

  Future<void> _scanAndPair() async {
    final payload = await Navigator.of(context).push<RelayPairingPayload>(
      MaterialPageRoute(builder: (_) => const PairScannerView()),
    );
    if (payload == null || !mounted) return;
    setState(() {
      _loading = true;
      _statusMessage = '正在建立端到端安全配对…';
    });
    try {
      final identity = await _client.claimPairing(payload);
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _pcOnline = true;
        _statusMessage = null;
      });
      DiagnosticLog.instance.record(
        '[pair] 配对成功 device=${_shortId(identity.deviceId)}',
        category: DiagnosticCategory.pairing,
      );
      _startStatusPolling();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = '配对失败：$error');
      DiagnosticLog.instance.record(
        '[pair] 配对失败：$error',
        category: DiagnosticCategory.pairing,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final identity = _identity;
    if (identity == null) {
      setState(() => _statusMessage = '请先扫描 Mac 端配对二维码');
      return;
    }
    if (_isFetching) return;
    _isFetching = true;
    if (!_loading) setState(() {}); // 刷新已有列表时不触发全屏转圈，保留内容可见。
    try {
      // 内容抓取前先复检注册状态：设备若已被删除则清本地回到扫码。
      await _checkRegistration(identity);
      final current = _identity;
      if (current == null) return;

      // 4 次退避重试（首次立即 + 2/4/8/16s），总等待 30s。
      // 仅对 503（Mac 连接已断开）/504（Mac 响应超时）重试；其它异常直接抛出。
      const backoffs = [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
      ];
      Object? lastError;
      for (final wait in backoffs) {
        if (wait > Duration.zero) await Future.delayed(wait);
        try {
          final response = await _client.query(current);
          if (!mounted) return;
          setState(() {
            _snapshots = response.snapshots;
            _pcOnline = true;
            _statusMessage = response.snapshots.isEmpty
                ? 'Mac 未返回可用 Provider 数据'
                : null;
          });
          if (response.snapshots.isEmpty) {
            DiagnosticLog.instance.record(
              '[query] 刷新成功但 snapshots 为空',
              category: DiagnosticCategory.query,
            );
          }
          _startStatusPolling();
          return; // 成功，退出重试循环。
        } on RelayClientException catch (e) {
          lastError = e;
          final msg = e.message;
          final retriable = const {
            'PC_DISCONNECTED',
            'PC_OFFLINE',
            'PC_SEND_FAILED',
            'SERVER_SHUTDOWN',
            'PC_RESPONSE_TIMEOUT',
          }.contains(e.code);
          if (!retriable) rethrow; // 401/429/400 等不重试。
          DiagnosticLog.instance.record(
            '[query] 重试中($wait)：$msg',
            category: DiagnosticCategory.query,
          );
        }
      }
      // 4 次都失败。
      if (!mounted) return;
      setState(() {
        _statusMessage = '查询失败：$lastError';
      });
      DiagnosticLog.instance.record(
        '[query] 4 次重试后仍失败：$lastError',
        category: DiagnosticCategory.query,
      );
      await _checkStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '查询失败：$error';
      });
      DiagnosticLog.instance.record(
        '[query] 查询失败：$error',
        category: DiagnosticCategory.query,
      );
      await _checkStatus();
    } finally {
      _isFetching = false;
      if (mounted) setState(() {});
    }
  }

  void _openDiagnostic() {
    if (!kDebugMode) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticView(relayEndpoint: widget.relayEndpoint),
      ),
    );
  }

  Future<void> _forgetDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忘记配对设备？'),
        content: const Text('将彻底删除服务器上的设备记录，并清除本机保存的 App Token 和端到端密钥。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('忘记设备'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final identity = _identity;
    if (identity != null) {
      try {
        await _client.deleteDevice(identity);
      } catch (_) {
        // 服务器删除失败不阻塞本地清理；下次查询会因 token 失效自然结束。
      }
    }
    await _store.delete();
    DiagnosticLog.instance.record(
      '[forget] 已忘记设备并清除本地配对',
      category: DiagnosticCategory.device,
    );
    if (!mounted) return;
    setState(() {
      _identity = null;
      _snapshots = const [];
      _pcOnline = false;
      _statusMessage = '请扫描 Mac 端生成的安全配对二维码';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('余额监控'),
        actions: [
          _ConnectionBadge(
            online: _pcOnline,
            paired: _identity != null,
            checking: _checkingStatus,
            onTap: _checkStatus,
          ),
          IconButton(
            onPressed: _scanAndPair,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '扫描配对',
          ),
          IconButton(
            onPressed: _isFetching ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新余额',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'forget') _forgetDevice();
              if (value == 'diagnostic') _openDiagnostic();
            },
            itemBuilder: (_) => [
              if (kDebugMode)
                const PopupMenuItem(value: 'diagnostic', child: Text('开发者诊断')),
              const PopupMenuItem(value: 'forget', child: Text('忘记设备')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _identity == null
          ? FloatingActionButton.extended(
              onPressed: _scanAndPair,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫描配对'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_snapshots.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          itemCount: _snapshots.length,
          itemBuilder: (_, index) => BalanceCard(snapshot: _snapshots[index]),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _identity == null
                  ? Icons.shield_outlined
                  : Icons.computer_outlined,
              size: 54,
            ),
            const SizedBox(height: 18),
            Text(_statusMessage ?? '没有可显示的数据', textAlign: TextAlign.center),
          ],
        ),
      ),
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
    this.checking = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = online
        ? Colors.green
        : (paired ? Colors.orange : Colors.grey);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Tooltip(
          message: '点击刷新连接状态',
          child: checking
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.circle, size: 10, color: color),
        ),
      ),
    );
  }
}
