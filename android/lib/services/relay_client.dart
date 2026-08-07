import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/relay_models.dart';
import 'diagnostic_log.dart';
import 'relay_crypto.dart';
import 'relay_identity_store.dart';

class RelayClient {
  final RelayIdentityPersistence store;
  final Uri serverBaseUrl;
  final http.Client httpClient;

  RelayClient(
    this.store, {
    required this.serverBaseUrl,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  Future<RelayIdentity> claimPairing(RelayPairingPayload payload) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .post(
            _endpointForBase(serverBaseUrl, 'api/v1/pair/claim'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': payload.deviceId,
              'pairCode': payload.pairCode,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[claim] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms',
        category: DiagnosticCategory.pairing,
      );
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '配对失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[claim] error: $error',
          category: DiagnosticCategory.pairing,
        );
        throw RelayClientException(error, code: code);
      }
      final appToken = body['appToken'] as String? ?? '';
      if (appToken.length < 40) {
        DiagnosticLog.instance.record(
          '[claim] error: 服务器返回的 App Token 无效',
          category: DiagnosticCategory.pairing,
        );
        throw const RelayClientException('服务器返回的 App Token 无效');
      }
      final identity = RelayIdentity(
        deviceId: payload.deviceId,
        appToken: appToken,
        e2eKey: payload.e2eKey,
      );
      await store.save(identity);
      DiagnosticLog.instance.record(
        '[claim] success, device=${_shortId(identity.deviceId)}',
        category: DiagnosticCategory.pairing,
      );
      return identity;
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[claim] connection failed',
        category: DiagnosticCategory.pairing,
      );
      throw const RelayClientException('中继连接失败', code: 'NETWORK_ERROR');
    }
  }

  Future<bool> online(RelayIdentity identity) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .get(
            _endpoint('api/v1/device/status'),
            headers: _authHeaders(identity),
          )
          .timeout(const Duration(seconds: 15));
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[online] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms path=api/v1/device/status',
        category: DiagnosticCategory.connection,
      );
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '状态查询失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[online] error: $error',
          category: DiagnosticCategory.connection,
        );
        throw RelayClientException(error, code: code);
      }
      final online = body['online'] as bool? ?? false;
      DiagnosticLog.instance.record(
        '[online] online=$online',
        category: DiagnosticCategory.connection,
      );
      return online;
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[online] connection failed',
        category: DiagnosticCategory.connection,
      );
      throw const RelayClientException('连接状态检查失败', code: 'NETWORK_ERROR');
    }
  }

  /// 用 App token 撤销服务器上的配对记录（忘记设备时调用）。
  Future<void> revoke(RelayIdentity identity) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .post(
            _endpoint('api/v1/devices/revoke'),
            headers: {
              ..._authHeaders(identity),
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[revoke] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms path=api/v1/devices/revoke',
        category: DiagnosticCategory.device,
      );
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '撤销失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[revoke] error: $error',
          category: DiagnosticCategory.device,
        );
        throw RelayClientException(error, code: code);
      }
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[revoke] connection failed',
        category: DiagnosticCategory.device,
      );
      throw const RelayClientException('撤销设备失败', code: 'NETWORK_ERROR');
    }
  }

  /// 彻底删除服务器上的设备记录（方案 B）。
  Future<void> deleteDevice(RelayIdentity identity) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .delete(_endpoint('api/v1/devices'), headers: _authHeaders(identity))
          .timeout(const Duration(seconds: 15));
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[delete] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms path=api/v1/devices',
        category: DiagnosticCategory.device,
      );
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '删除设备失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[delete] error: $error',
          category: DiagnosticCategory.device,
        );
        throw RelayClientException(error, code: code);
      }
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[delete] connection failed',
        category: DiagnosticCategory.device,
      );
      throw const RelayClientException('删除设备失败', code: 'NETWORK_ERROR');
    }
  }

  /// 注册状态检测（3 态）。
  /// 返回 null 表示设备不存在（404），true/false 表示已注册/未注册。
  Future<bool?> registrationStatus(RelayIdentity identity) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .post(
            _endpoint('api/v1/device/registration-status'),
            headers: {
              ..._authHeaders(identity),
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[registration] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms path=api/v1/device/registration-status',
        category: DiagnosticCategory.registration,
      );
      if (response.statusCode == 404) {
        DiagnosticLog.instance.record(
          '[registration] device_not_found',
          category: DiagnosticCategory.registration,
        );
        return null; // device_not_found
      }
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '注册状态检测失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[registration] error: $error',
          category: DiagnosticCategory.registration,
        );
        throw RelayClientException(error, code: code);
      }
      final registered = body['registered'] as bool? ?? false;
      DiagnosticLog.instance.record(
        '[registration] registered=$registered',
        category: DiagnosticCategory.registration,
      );
      return registered;
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[registration] connection failed',
        category: DiagnosticCategory.registration,
      );
      throw const RelayClientException('注册状态检测失败', code: 'NETWORK_ERROR');
    }
  }

  Future<RelayBalanceResponse> query(RelayIdentity identity) async {
    final stopwatch = Stopwatch()..start();
    try {
      final requestId = RelayCrypto.randomId();
      final query = RelayQuery(
        issuedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
        nonce: RelayCrypto.randomId(24),
      );
      final envelope = RelayCrypto.seal(query.toJson(), identity.e2eKey);
      DiagnosticLog.instance.record(
        '[query] request start requestId=${requestId.substring(0, 8)} path=api/v1/relay/query',
        category: DiagnosticCategory.query,
      );
      final response = await httpClient
          .post(
            _endpoint('api/v1/relay/query'),
            headers: {
              ..._authHeaders(identity),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'requestId': requestId,
              'envelope': envelope.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 50));
      if (response.bodyBytes.length > 65_536) {
        DiagnosticLog.instance.record(
          '[query] error: 中继响应过大',
          category: DiagnosticCategory.query,
        );
        throw const RelayClientException('中继响应过大');
      }
      final body = _json(response);
      DiagnosticLog.instance.record(
        '[query] ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms',
        category: DiagnosticCategory.query,
      );
      if (response.statusCode != 200) {
        final error = body['error'] as String? ?? '余额查询失败';
        final code = body['code'] as String?;
        DiagnosticLog.instance.record(
          '[query] error: $error',
          category: DiagnosticCategory.query,
        );
        if (const {
          'PC_DISCONNECTED',
          'PC_OFFLINE',
          'PC_SEND_FAILED',
          'SERVER_SHUTDOWN',
        }.contains(code)) {
          DiagnosticLog.instance.record(
            '[query] Mac connection unavailable code=$code',
            category: DiagnosticCategory.query,
          );
          throw RelayClientException('Mac 连接已断开，请确认 Mac 端在线', code: code);
        }
        if (code == 'PC_RESPONSE_TIMEOUT') {
          throw const RelayClientException(
            'Mac 响应超时，请稍后重试',
            code: 'PC_RESPONSE_TIMEOUT',
          );
        }
        throw RelayClientException(error, code: code);
      }
      if (body['requestId'] != requestId) {
        DiagnosticLog.instance.record(
          '[query] requestId 不匹配',
          category: DiagnosticCategory.query,
        );
        throw const RelayClientException('中继响应 requestId 不匹配');
      }
      final responseEnvelope = RelayOpaqueEnvelope.fromJson(
        body['envelope'] as Map<String, dynamic>,
      );
      DiagnosticLog.instance.record(
        '[query] 解密开始 ${stopwatch.elapsedMilliseconds}ms',
        category: DiagnosticCategory.query,
      );
      final plaintext = RelayCrypto.open(responseEnvelope, identity.e2eKey);
      final result = RelayBalanceResponse.fromJson(plaintext);
      final providers = result.snapshots
          .map((s) => s.provider?.rawValue ?? 'unknown')
          .join(', ');
      DiagnosticLog.instance.record(
        '[query] ok ${stopwatch.elapsedMilliseconds}ms, snapshots=${result.snapshots.length} [$providers]',
        category: DiagnosticCategory.query,
      );
      return result;
    } catch (error) {
      if (error is RelayClientException) rethrow;
      DiagnosticLog.instance.record(
        '[query] connection failed',
        category: DiagnosticCategory.query,
      );
      throw const RelayClientException('余额查询失败', code: 'NETWORK_ERROR');
    }
  }

  Map<String, String> _authHeaders(RelayIdentity identity) => {
    'Authorization': 'Bearer ${identity.appToken}',
    'X-Device-Id': identity.deviceId,
  };

  static String _shortId(String deviceId) =>
      deviceId.length <= 8 ? deviceId : '${deviceId.substring(0, 8)}…';

  Uri _endpoint(String path) {
    return _endpointForBase(serverBaseUrl, path);
  }

  Uri _endpointForBase(Uri serverBaseUrl, String path) {
    final base = serverBaseUrl.toString();
    return Uri.parse('${base.endsWith('/') ? base : '$base/'}$path');
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.bodyBytes.length > 65_536) {
      throw const RelayClientException('服务器响应过大');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const RelayClientException('服务器响应格式无效');
    }
  }
}

class RelayClientException implements Exception {
  final String message;
  final String? code;
  const RelayClientException(this.message, {this.code});
  @override
  String toString() => message;
}
