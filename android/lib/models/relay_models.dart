import 'balance_snapshot.dart';
import 'package:relay_core/relay_core.dart';

export 'package:relay_core/relay_core.dart'
    show
        RelayDeviceStatus,
        RelayEncodedSection,
        RelayIdentity,
        RelayOpaqueEnvelope,
        RelayPairingPayload,
        RelayQuery,
        RelayRegistrationStatus,
        RelayTerminalInfo,
        RelayTerminalState,
        RelayWireError;

class RelayBalanceResponse {
  final int generatedAtMilliseconds;
  final List<BalanceSnapshot> snapshots;
  final String requestNonce;
  final Map<String, dynamic> sections;
  final RelayWireError? error;

  RelayBalanceResponse({
    required this.generatedAtMilliseconds,
    required this.snapshots,
    required this.requestNonce,
    this.sections = const {},
    this.error,
  });

  factory RelayBalanceResponse.fromJson(Map<String, dynamic> json) {
    final snapshots = (json['snapshots'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          try {
            return BalanceSnapshot.fromJson(item);
          } catch (_) {
            // 单个 snapshot 解析失败（如未知 provider）时跳过，避免整个响应失败。
            return null;
          }
        })
        .whereType<BalanceSnapshot>()
        // 未知 provider（provider 为 null）不展示，避免出现"未知 Provider"卡片。
        .where((s) => s.provider != null)
        .toList();
    return RelayBalanceResponse(
      generatedAtMilliseconds:
          (json['generatedAtMilliseconds'] as num?)?.toInt() ?? 0,
      snapshots: snapshots,
      requestNonce: json['requestNonce'] as String? ?? '',
      sections: (json['sections'] as Map<String, dynamic>?) ?? const {},
      error: json['error'] is Map<String, dynamic>
          ? RelayWireError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }

  RelayBalanceResponse merge(RelayBalanceResponse other) {
    return RelayBalanceResponse(
      generatedAtMilliseconds: other.generatedAtMilliseconds,
      snapshots: other.snapshots.isNotEmpty ? other.snapshots : snapshots,
      requestNonce: other.requestNonce,
      sections: {...sections, ...other.sections},
      error: other.error,
    );
  }
}
