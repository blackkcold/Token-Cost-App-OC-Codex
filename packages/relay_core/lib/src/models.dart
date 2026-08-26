import 'dart:convert';
import 'dart:typed_data';

enum RelayTerminalState {
  pending('PENDING'),
  active('ACTIVE'),
  expired('EXPIRED'),
  revoked('REVOKED'),
  replaced('REPLACED');

  const RelayTerminalState(this.wireValue);
  final String wireValue;

  static RelayTerminalState parse(Object? value) {
    return RelayTerminalState.values.firstWhere(
      (state) => state.wireValue == value,
      orElse: () => throw const FormatException('终端状态无效'),
    );
  }
}

class RelayPairingPayload {
  RelayPairingPayload({
    required this.version,
    required this.deviceId,
    required this.keyVersion,
    required this.pairCode,
    required this.e2eKey,
    required this.expiresAtMilliseconds,
  });

  final int version;
  final String deviceId;
  final int keyVersion;
  final String pairCode;
  final Uint8List e2eKey;
  final int expiresAtMilliseconds;

  static RelayPairingPayload parse(String value, {int? nowMilliseconds}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'balance-relay' ||
        uri.host != 'pair' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParametersAll.keys.length != 1 ||
        !uri.queryParametersAll.containsKey('data') ||
        uri.queryParametersAll['data']?.length != 1) {
      throw const FormatException('不是余额中继配对二维码');
    }
    final encoded = uri.queryParametersAll['data']!.single;
    if (encoded.isEmpty || encoded.length > 8192) {
      throw const FormatException('二维码数据缺失');
    }
    late Map<String, dynamic> payload;
    try {
      final normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
      final decoded = jsonDecode(utf8.decode(base64.decode(padded)));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } catch (_) {
      throw const FormatException('二维码数据无法解析');
    }
    const allowedFields = {
      'version',
      'deviceID',
      'keyVersion',
      'pairCode',
      'e2eKey',
      'expiresAtMilliseconds',
    };
    if (payload.containsKey('serverBaseURL')) {
      throw const FormatException('配对二维码包含不受支持的服务器字段');
    }
    if (payload.keys.any((key) => !allowedFields.contains(key))) {
      throw const FormatException('配对二维码包含不受支持的字段');
    }
    if (payload['version'] != 1) throw const FormatException('不支持的配对版本');
    final deviceId = payload['deviceID'];
    if (deviceId is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{16,80}$').hasMatch(deviceId)) {
      throw const FormatException('设备 ID 无效');
    }
    final keyVersion = payload['keyVersion'];
    if (keyVersion is! int || keyVersion < 1) {
      throw const FormatException('密钥版本无效');
    }
    final pairCode = payload['pairCode'];
    if (pairCode is! String || pairCode.length < 24 || pairCode.length > 100) {
      throw const FormatException('配对码无效');
    }
    late Uint8List key;
    try {
      key = Uint8List.fromList(base64.decode(payload['e2eKey'] as String));
    } catch (_) {
      throw const FormatException('端到端密钥无效');
    }
    if (key.length != 32) throw const FormatException('端到端密钥长度不符');
    final expiresAt = (payload['expiresAtMilliseconds'] as num?)?.toInt() ?? 0;
    final now = nowMilliseconds ?? DateTime.now().millisecondsSinceEpoch;
    if (expiresAt <= now) throw const FormatException('配对二维码已过期');
    return RelayPairingPayload(
      version: 1,
      deviceId: deviceId,
      keyVersion: keyVersion,
      pairCode: pairCode,
      e2eKey: key,
      expiresAtMilliseconds: expiresAt,
    );
  }
}

class RelayIdentity {
  RelayIdentity({
    required this.deviceId,
    required this.appToken,
    required this.e2eKey,
    this.keyVersion = 1,
    this.terminalState = RelayTerminalState.active,
  });

  final String deviceId;
  final String appToken;
  final Uint8List e2eKey;
  final int keyVersion;
  final RelayTerminalState terminalState;

  RelayIdentity copyWith({RelayTerminalState? terminalState}) => RelayIdentity(
        deviceId: deviceId,
        appToken: appToken,
        e2eKey: e2eKey,
        keyVersion: keyVersion,
        terminalState: terminalState ?? this.terminalState,
      );
}

class RelayTerminalInfo {
  const RelayTerminalInfo({
    required this.keyVersion,
    required this.state,
    this.activationExpiresAt,
    this.lastUserActivityAt,
    this.expiresAt,
  });

  factory RelayTerminalInfo.fromJson(Map<String, dynamic> json) {
    final keyVersion = json['keyVersion'];
    if (keyVersion is! int || keyVersion < 1) {
      throw const FormatException('终端密钥版本无效');
    }
    return RelayTerminalInfo(
      keyVersion: keyVersion,
      state: RelayTerminalState.parse(json['state'] ?? json['terminalState']),
      activationExpiresAt: (json['activationExpiresAt'] as num?)?.toInt(),
      lastUserActivityAt: (json['lastUserActivityAt'] as num?)?.toInt(),
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
    );
  }

  final int keyVersion;
  final RelayTerminalState state;
  final int? activationExpiresAt;
  final int? lastUserActivityAt;
  final int? expiresAt;
}

class RelayDeviceStatus {
  const RelayDeviceStatus({
    required this.deviceId,
    required this.online,
    required this.appOnline,
    required this.appLastSeenAt,
    required this.terminal,
  });

  factory RelayDeviceStatus.fromJson(Map<String, dynamic> json) =>
      RelayDeviceStatus(
        deviceId: json['deviceId'] as String? ?? '',
        online: json['online'] as bool? ?? false,
        appOnline: json['appOnline'] as bool? ?? false,
        appLastSeenAt: (json['appLastSeenAt'] as num?)?.toInt() ?? 0,
        terminal: RelayTerminalInfo.fromJson(
            json['terminal'] as Map<String, dynamic>),
      );

  final String deviceId;
  final bool online;
  final bool appOnline;
  final int appLastSeenAt;
  final RelayTerminalInfo terminal;
}

class RelayRegistrationStatus {
  const RelayRegistrationStatus({
    required this.registered,
    required this.paired,
    required this.disabled,
    this.keyVersion,
    this.terminalState,
  });

  final bool registered;
  final bool paired;
  final bool disabled;
  final int? keyVersion;
  final RelayTerminalState? terminalState;
}

class RelayOpaqueEnvelope {
  RelayOpaqueEnvelope({
    this.v = 1,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  factory RelayOpaqueEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('不支持的中继信封版本');
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final tag = json['tag'];
    if (nonce is! String || ciphertext is! String || tag is! String) {
      throw const FormatException('中继信封字段无效');
    }
    return RelayOpaqueEnvelope(nonce: nonce, ciphertext: ciphertext, tag: tag);
  }

  final int v;
  final String nonce;
  final String ciphertext;
  final String tag;

  Map<String, dynamic> toJson() => {
        'v': v,
        'nonce': nonce,
        'ciphertext': ciphertext,
        'tag': tag,
      };
}

class RelayQuery {
  RelayQuery({
    this.action = 'balance.refresh',
    required this.issuedAtMilliseconds,
    required this.nonce,
    this.requestedSections,
    this.sectionParams,
  });

  final String action;
  final int issuedAtMilliseconds;
  final String nonce;
  final List<String>? requestedSections;
  final Map<String, dynamic>? sectionParams;

  Map<String, dynamic> toJson() => {
        'action': action,
        'issuedAtMilliseconds': issuedAtMilliseconds,
        'nonce': nonce,
        if (requestedSections != null) 'requestedSections': requestedSections,
        if (sectionParams != null) 'sectionParams': sectionParams,
      };
}

class RelayEncodedSection {
  const RelayEncodedSection({
    required this.encoding,
    required this.uncompressedBytes,
    required this.data,
  });

  factory RelayEncodedSection.fromJson(Map<String, dynamic> json) =>
      RelayEncodedSection(
        encoding: json['encoding'] as String? ?? '',
        uncompressedBytes: (json['uncompressedBytes'] as num?)?.toInt() ?? -1,
        data: json['data'] as String? ?? '',
      );

  final String encoding;
  final int uncompressedBytes;
  final String data;
}

class RelayWireError {
  const RelayWireError({required this.code, required this.message});

  factory RelayWireError.fromJson(Map<String, dynamic> json) => RelayWireError(
        code: json['code'] as String? ?? 'INVALID_REQUEST',
        message: json['message'] as String? ?? 'Relay request failed',
      );

  final String code;
  final String message;
}
