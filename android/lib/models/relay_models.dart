import 'dart:convert';
import 'dart:typed_data';

import 'balance_snapshot.dart';

class RelayPairingPayload {
  final int version;
  final String deviceId;
  final String pairCode;
  final Uint8List e2eKey;
  final int expiresAtMilliseconds;

  RelayPairingPayload({
    required this.version,
    required this.deviceId,
    required this.pairCode,
    required this.e2eKey,
    required this.expiresAtMilliseconds,
  });

  static RelayPairingPayload parse(String value, {int? nowMilliseconds}) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'balance-relay' || uri.host != 'pair') {
      throw const FormatException('不是余额中继配对二维码');
    }
    final encoded = uri.queryParameters['data'];
    if (encoded == null || encoded.isEmpty || encoded.length > 8192) {
      throw const FormatException('二维码数据缺失');
    }
    Map<String, dynamic> json;
    try {
      // macOS 端 JSONEncoder 对 Data 输出标准 base64；此处兼容 base64url 与标准 base64。
      final normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
      json =
          jsonDecode(utf8.decode(base64.decode(padded)))
              as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('二维码数据无法解析');
    }
    if (json['version'] != 1) {
      throw const FormatException('不支持的配对版本');
    }
    if (json.containsKey('serverBaseURL')) {
      throw const FormatException('配对二维码包含不受支持的服务器字段');
    }
    final deviceId = json['deviceID'] as String? ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{16,80}$').hasMatch(deviceId)) {
      throw const FormatException('设备 ID 无效');
    }
    final pairCode = json['pairCode'] as String? ?? '';
    if (pairCode.length < 24 || pairCode.length > 100) {
      throw const FormatException('配对码无效');
    }
    Uint8List key;
    try {
      key = Uint8List.fromList(base64.decode(json['e2eKey'] as String? ?? ''));
    } catch (_) {
      throw const FormatException('端到端密钥无效');
    }
    if (key.length != 32) {
      throw const FormatException('端到端密钥长度不符');
    }
    final expiresAt = (json['expiresAtMilliseconds'] as num?)?.toInt() ?? 0;
    final now = nowMilliseconds ?? DateTime.now().millisecondsSinceEpoch;
    if (expiresAt <= now) {
      throw const FormatException('配对二维码已过期');
    }
    return RelayPairingPayload(
      version: 1,
      deviceId: deviceId,
      pairCode: pairCode,
      e2eKey: key,
      expiresAtMilliseconds: expiresAt,
    );
  }
}

class RelayIdentity {
  final String deviceId;
  final String appToken;
  final Uint8List e2eKey;

  RelayIdentity({
    required this.deviceId,
    required this.appToken,
    required this.e2eKey,
  });
}

class RelayOpaqueEnvelope {
  final int v;
  final String nonce;
  final String ciphertext;
  final String tag;

  RelayOpaqueEnvelope({
    this.v = 1,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  factory RelayOpaqueEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('不支持的中继信封版本');
    return RelayOpaqueEnvelope(
      nonce: json['nonce'] as String? ?? '',
      ciphertext: json['ciphertext'] as String? ?? '',
      tag: json['tag'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'v': v,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'tag': tag,
  };
}

class RelayQuery {
  final String action;
  final int issuedAtMilliseconds;
  final String nonce;
  final List<String>? requestedSections;
  final Map<String, dynamic>? sectionParams;

  RelayQuery({
    this.action = 'balance.refresh',
    required this.issuedAtMilliseconds,
    required this.nonce,
    this.requestedSections,
    this.sectionParams,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'issuedAtMilliseconds': issuedAtMilliseconds,
    'nonce': nonce,
    if (requestedSections != null) 'requestedSections': requestedSections,
    if (sectionParams != null) 'sectionParams': sectionParams,
  };
}

class RelayEncodedSection {
  final String encoding;
  final int uncompressedBytes;
  final String data;

  const RelayEncodedSection({
    required this.encoding,
    required this.uncompressedBytes,
    required this.data,
  });

  factory RelayEncodedSection.fromJson(Map<String, dynamic> json) {
    return RelayEncodedSection(
      encoding: json['encoding'] as String? ?? '',
      uncompressedBytes: (json['uncompressedBytes'] as num?)?.toInt() ?? -1,
      data: json['data'] as String? ?? '',
    );
  }
}

class RelayWireError {
  final String code;
  final String message;

  const RelayWireError({required this.code, required this.message});

  factory RelayWireError.fromJson(Map<String, dynamic> json) => RelayWireError(
    code: json['code'] as String? ?? 'INVALID_REQUEST',
    message: json['message'] as String? ?? 'Relay request failed',
  );
}

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
