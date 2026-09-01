import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/analytics_sections.dart';
import '../models/balance_snapshot.dart';
import '../models/relay_models.dart';
import '../services/diagnostic_log.dart';
import '../services/relay_client.dart';
import '../services/relay_identity_store.dart';
import '../services/relay_section_cache.dart';

const offlineStatusMessage = '已配对，但 Mac 当前离线';
const reconnectedStatusMessage = 'Mac 已重新连接，请再次刷新余额';
const queryRecoveredStatusMessage = 'Mac 已连接，但上次查询超时，请再次刷新余额';

String? statusMessageAfterOnlineCheck({
  required bool online,
  required String? currentMessage,
}) {
  if (!online) return currentMessage ?? offlineStatusMessage;
  if (currentMessage == null ||
      currentMessage == offlineStatusMessage ||
      currentMessage.startsWith('连接检查失败：')) {
    return null;
  }
  if (currentMessage.contains('Mac 连接已断开')) {
    return reconnectedStatusMessage;
  }
  if (currentMessage.contains('Mac 响应超时')) {
    return queryRecoveredStatusMessage;
  }
  return currentMessage;
}

String terminalStateMessage(RelayTerminalState state, {required bool online}) {
  return switch (state) {
    RelayTerminalState.pending => '等待 Mac 确认并激活此终端',
    RelayTerminalState.active => online ? 'Mac 已连接' : offlineStatusMessage,
    RelayTerminalState.expired => '终端已因七天未使用而过期，请重新扫码配对',
    RelayTerminalState.revoked => '终端已被撤销，请重新扫码配对',
    RelayTerminalState.replaced => '终端已被新的手机替换，请重新扫码配对',
  };
}

class DashboardStore extends ChangeNotifier {
  final Uri relayEndpoint;
  late final RelayIdentityStore identityStore;
  late final RelayClient relayClient;
  late final RelaySectionCache sectionCache;

  RelayIdentity? identity;
  List<BalanceSnapshot> snapshots = const [];
  Map<String, dynamic> rawSections = const {};
  AnalyticsSections analytics = const AnalyticsSections();
  bool loading = true;
  bool isFetching = false;
  bool pcOnline = false;
  bool checkingStatus = false;
  String? statusMessage;
  DateTime? lastUpdatedAt;

  Timer? _statusTimer;
  bool _disposed = false;

  DashboardStore({required this.relayEndpoint}) {
    identityStore = RelayIdentityStore(expectedServerBaseUrl: relayEndpoint);
    relayClient = RelayClient(identityStore, serverBaseUrl: relayEndpoint);
    sectionCache = RelaySectionCache();
  }

  bool get isPaired => identity != null;
  bool get hasContent => snapshots.isNotEmpty || !analytics.isEmpty;

  Future<void> initialize() async {
    identity = await identityStore.load();
    loading = false;
    statusMessage = identity == null ? '请扫描 Mac 端生成的安全配对二维码' : null;
    _notify();
    final current = identity;
    if (current == null) {
      DiagnosticLog.instance.record(
        '[init] 未找到本地配对身份',
        category: DiagnosticCategory.connection,
      );
      return;
    }

    final cached = await sectionCache.load(current.deviceId);
    if (cached != null) _applySections(cached.sections);
    DiagnosticLog.instance.record(
      '[init] 已加载配对身份 device=${_shortId(current.deviceId)}',
      category: DiagnosticCategory.connection,
    );
    await _checkRegistration(current);
    if (identity == null) return;
    await checkStatus();
    _startStatusPolling();
    if (identity?.terminalState == RelayTerminalState.active) await refresh();
  }

  Future<void> claimPairing(RelayPairingPayload payload) async {
    loading = true;
    statusMessage = '正在建立端到端安全配对…';
    _notify();
    try {
      final claimed = await relayClient.claimPairing(payload);
      identity = claimed;
      pcOnline = false;
      statusMessage = terminalStateMessage(
        claimed.terminalState,
        online: false,
      );
      DiagnosticLog.instance.record(
        '[pair] 配对成功 device=${_shortId(claimed.deviceId)}',
        category: DiagnosticCategory.pairing,
      );
      _startStatusPolling();
      await checkStatus();
    } catch (error) {
      statusMessage = '配对失败：$error';
      DiagnosticLog.instance.record(
        '[pair] 配对失败：$error',
        category: DiagnosticCategory.pairing,
      );
      rethrow;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> checkStatus() async {
    final current = identity;
    if (current == null || checkingStatus) return;
    checkingStatus = true;
    _notify();
    try {
      final status = await relayClient.deviceStatus(current);
      final updated = current.copyWith(terminalState: status.terminal.state);
      await identityStore.save(updated);
      final becameActive =
          current.terminalState != RelayTerminalState.active &&
          updated.terminalState == RelayTerminalState.active;
      identity = updated;
      pcOnline =
          updated.terminalState == RelayTerminalState.active && status.online;
      statusMessage = updated.terminalState == RelayTerminalState.active
          ? statusMessageAfterOnlineCheck(
              online: status.online,
              currentMessage: statusMessage,
            )
          : terminalStateMessage(updated.terminalState, online: false);
      if (becameActive) unawaited(refresh());
    } catch (error) {
      pcOnline = false;
      statusMessage = '连接检查失败：$error';
      DiagnosticLog.instance.record(
        '[online] 连接检查失败：$error',
        category: DiagnosticCategory.connection,
      );
    } finally {
      checkingStatus = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    final currentIdentity = identity;
    if (currentIdentity == null) {
      statusMessage = '请先扫描 Mac 端配对二维码';
      _notify();
      return;
    }
    if (currentIdentity.terminalState != RelayTerminalState.active) {
      statusMessage = terminalStateMessage(
        currentIdentity.terminalState,
        online: false,
      );
      _notify();
      return;
    }
    if (isFetching) return;
    isFetching = true;
    _notify();
    try {
      await _checkRegistration(currentIdentity);
      final current = identity;
      if (current == null) return;
      const backoffs = [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
      ];
      Object? lastError;
      for (final wait in backoffs) {
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        try {
          final response = await relayClient.query(current);
          snapshots = response.snapshots;
          _applySections(response.sections);
          pcOnline = true;
          lastUpdatedAt = DateTime.now();
          statusMessage = response.snapshots.isEmpty && analytics.isEmpty
              ? 'Mac 未返回可用 Provider 或分析数据'
              : null;
          await sectionCache.save(current.deviceId, response);
          _startStatusPolling();
          return;
        } on RelayClientException catch (error) {
          lastError = error;
          if (!const {
            'PC_DISCONNECTED',
            'PC_OFFLINE',
            'PC_SEND_FAILED',
            'SERVER_SHUTDOWN',
            'PC_RESPONSE_TIMEOUT',
          }.contains(error.code)) {
            rethrow;
          }
        }
      }
      statusMessage = '查询失败：$lastError';
      await checkStatus();
    } catch (error) {
      statusMessage = '查询失败：$error';
      DiagnosticLog.instance.record(
        '[query] 查询失败：$error',
        category: DiagnosticCategory.query,
      );
      await checkStatus();
    } finally {
      isFetching = false;
      _notify();
    }
  }

  Future<bool> revokeAndForget() async {
    final current = identity;
    if (current != null) {
      try {
        await relayClient.revoke(current);
      } on RelayClientException catch (error) {
        if (!const {
          'TERMINAL_EXPIRED',
          'TERMINAL_REVOKED',
          'TERMINAL_NOT_ACTIVE',
        }.contains(error.code)) {
          statusMessage = '撤销失败，已保留本地凭据以便重试：$error';
          _notify();
          return false;
        }
      } catch (error) {
        statusMessage = '撤销失败，已保留本地凭据以便重试：$error';
        _notify();
        return false;
      }
    }
    await identityStore.delete();
    await sectionCache.delete();
    identity = null;
    snapshots = const [];
    rawSections = const {};
    analytics = const AnalyticsSections();
    pcOnline = false;
    statusMessage = '请扫描 Mac 端生成的安全配对二维码';
    _statusTimer?.cancel();
    _notify();
    return true;
  }

  Future<void> _checkRegistration(RelayIdentity current) async {
    try {
      final registration = await relayClient.registrationStatus(current);
      if (registration == null) {
        await identityStore.delete();
        await sectionCache.delete();
        identity = null;
        snapshots = const [];
        rawSections = const {};
        analytics = const AnalyticsSections();
        pcOnline = false;
        statusMessage = '设备已在 Mac 端删除，请重新扫描配对二维码';
        _notify();
        return;
      }
      final state = registration.terminalState;
      if (state != null) {
        final updated = current.copyWith(terminalState: state);
        await identityStore.save(updated);
        identity = updated;
        if (state != RelayTerminalState.active) {
          pcOnline = false;
          statusMessage = terminalStateMessage(state, online: false);
        }
      }
    } catch (_) {
      // 网络失败不删除本地身份，等待下一次状态检查。
    }
  }

  void _applySections(Map<String, dynamic> sections) {
    rawSections = Map.unmodifiable(sections);
    analytics = AnalyticsSections.parse(sections);
    if (analytics.errors.isNotEmpty) {
      DiagnosticLog.instance.record(
        '[sections] 部分解析失败：${analytics.errors.join(',')}',
        category: DiagnosticCategory.query,
      );
    }
    _notify();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(checkStatus()),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _shortId(String deviceId) =>
      deviceId.length <= 8 ? deviceId : '${deviceId.substring(0, 8)}…';

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    relayClient.dispose();
    super.dispose();
  }
}
