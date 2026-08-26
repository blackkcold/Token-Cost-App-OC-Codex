import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class RelayApiException implements Exception {
  const RelayApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class RelayApiClient {
  RelayApiClient({
    required this.serverBaseUrl,
    http.Client? httpClient,
    this.maxTransportBytes = 65536,
  }) : httpClient = httpClient ?? http.Client();

  final Uri serverBaseUrl;
  final http.Client httpClient;
  final int maxTransportBytes;

  Future<RelayIdentity> claimPairing(
    RelayPairingPayload payload, {
    required String clientKind,
  }) async {
    if (!{'android', 'web'}.contains(clientKind)) {
      throw ArgumentError.value(clientKind, 'clientKind', 'must be android or web');
    }
    final body = await _sendJson(
      'POST',
      'api/v1/pair/claim',
      body: {
        'deviceId': payload.deviceId,
        'pairCode': payload.pairCode,
        'keyVersion': payload.keyVersion,
        'clientKind': clientKind,
      },
    );
    final appToken = body['appToken'];
    final keyVersion = body['keyVersion'];
    if (appToken is! String || appToken.length < 40 || keyVersion != payload.keyVersion) {
      throw const RelayApiException('服务器返回的终端凭据无效', code: 'INVALID_RESPONSE');
    }
    return RelayIdentity(
      deviceId: payload.deviceId,
      appToken: appToken,
      e2eKey: payload.e2eKey,
      keyVersion: payload.keyVersion,
      terminalState: RelayTerminalState.parse(body['terminalState']),
    );
  }

  Future<RelayDeviceStatus> deviceStatus(RelayIdentity identity) async {
    final body = await _sendJson('GET', 'api/v1/device/status', identity: identity);
    return RelayDeviceStatus.fromJson(body);
  }

  Future<RelayRegistrationStatus?> registrationStatus(RelayIdentity identity) async {
    try {
      final body = await _sendJson(
        'POST',
        'api/v1/device/registration-status',
        identity: identity,
        body: const {},
      );
      final stateValue = body['terminalState'];
      return RelayRegistrationStatus(
        registered: body['registered'] as bool? ?? false,
        paired: body['paired'] as bool? ?? false,
        disabled: body['disabled'] as bool? ?? false,
        keyVersion: (body['keyVersion'] as num?)?.toInt(),
        terminalState: stateValue == null ? null : RelayTerminalState.parse(stateValue),
      );
    } on RelayApiException catch (error) {
      if (error.statusCode == 404 && error.code == 'DEVICE_NOT_FOUND') return null;
      rethrow;
    }
  }

  Future<RelayTerminalInfo> revokeTerminal(RelayIdentity identity) async {
    final body = await _sendJson(
      'POST',
      'api/v1/terminal/revoke',
      identity: identity,
      body: {'keyVersion': identity.keyVersion},
    );
    return RelayTerminalInfo.fromJson(body);
  }

  Future<void> deleteDevice(RelayIdentity identity) async {
    await _sendJson('DELETE', 'api/v1/devices', identity: identity);
  }

  Future<RelayOpaqueEnvelope> queryEnvelope({
    required RelayIdentity identity,
    required String requestId,
    required RelayOpaqueEnvelope envelope,
  }) async {
    final body = await _sendJson(
      'POST',
      'api/v1/relay/query',
      identity: identity,
      headers: const {'X-Relay-Contract': '1.2.0'},
      body: {
        'requestId': requestId,
        'keyVersion': identity.keyVersion,
        'envelope': envelope.toJson(),
      },
    );
    if (body['requestId'] != requestId || body['keyVersion'] != identity.keyVersion) {
      throw const RelayApiException('中继响应绑定不匹配', code: 'REQUEST_REPLAYED');
    }
    final responseEnvelope = body['envelope'];
    if (responseEnvelope is! Map<String, dynamic>) {
      throw const RelayApiException('中继响应信封无效', code: 'INVALID_RESPONSE');
    }
    return RelayOpaqueEnvelope.fromJson(responseEnvelope);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    RelayIdentity? identity,
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, _endpoint(path));
    request.headers.addAll({
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (identity != null) ...{
        'Authorization': 'Bearer ${identity.appToken}',
        'X-Device-Id': identity.deviceId,
      },
      ...headers,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await httpClient.send(request).timeout(const Duration(seconds: 50));
    if (response.contentLength != null && response.contentLength! > maxTransportBytes) {
      throw const RelayApiException('中继响应过大', code: 'RESPONSE_TOO_LARGE');
    }
    final bytes = await _readBounded(response.stream);
    late Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } catch (_) {
      throw RelayApiException('服务器响应格式无效', code: 'INVALID_RESPONSE', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RelayApiException(
        decoded['error'] as String? ?? 'Relay request failed',
        code: decoded['code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<Uint8List> _readBounded(http.ByteStream stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
      if (builder.length + chunk.length > maxTransportBytes) {
        throw const RelayApiException('中继响应过大', code: 'RESPONSE_TOO_LARGE');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Uri _endpoint(String path) {
    final base = serverBaseUrl.toString();
    return Uri.parse('${base.endsWith('/') ? base : '$base/'}$path');
  }
}
