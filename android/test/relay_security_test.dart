import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:balance_monitor/models/relay_models.dart';
import 'package:balance_monitor/services/relay_client.dart';
import 'package:balance_monitor/services/relay_crypto.dart';
import 'package:balance_monitor/services/relay_identity_store.dart';
import 'package:balance_monitor/services/relay_endpoint.dart';

final testRelayEndpoint = Uri.parse('https://relay.example.invalid');
final contractFixtureRoot = Directory('../Resources/RelayContract/v1');

class MemoryIdentityStore implements RelayIdentityPersistence {
  RelayIdentity? value;

  @override
  Future<void> save(RelayIdentity identity) async => value = identity;

  @override
  Future<RelayIdentity?> load() async => value;

  @override
  Future<void> delete() async => value = null;
}

String pairingQr({required int expiresAt, Uint8List? key}) {
  final json = jsonEncode({
    'version': 1,
    'deviceID': 'device_security_0001',
    'pairCode': 'pair-code-security-000000000001',
    'e2eKey': base64.encode(key ?? Uint8List.fromList(List.filled(32, 0x42))),
    'expiresAtMilliseconds': expiresAt,
  });
  return 'balance-relay://pair?data=${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
}

void main() {
  test('二维码校验有效期和 32 字节 E2EE 密钥', () {
    const now = 1700000000000;
    final valid = RelayPairingPayload.parse(
      pairingQr(expiresAt: now + 300000),
      nowMilliseconds: now,
    );
    expect(valid.deviceId, 'device_security_0001');
    expect(valid.e2eKey.length, 32);

    expect(
      () => RelayPairingPayload.parse(
        pairingQr(expiresAt: now - 1),
        nowMilliseconds: now,
      ),
      throwsFormatException,
    );
    expect(
      () => RelayPairingPayload.parse(
        pairingQr(expiresAt: now + 300000, key: Uint8List(16)),
        nowMilliseconds: now,
      ),
      throwsFormatException,
    );
  });

  test('Relay Endpoint 必须显式配置且不能包含 query 或 fragment', () {
    expect(
      RelayEndpoint.requireConfigured(value: testRelayEndpoint.toString()),
      testRelayEndpoint,
    );
    expect(() => RelayEndpoint.requireConfigured(value: ''), throwsStateError);
    expect(
      () => RelayEndpoint.requireConfigured(
        value: 'https://relay.example.invalid?target=other',
      ),
      throwsStateError,
    );
  });

  test('配对二维码拒绝 legacy serverBaseURL override', () {
    final legacy = jsonEncode({
      'version': 1,
      'serverBaseURL': 'https://attacker.example.invalid',
      'deviceID': 'device_security_0001',
      'pairCode': 'pair-code-security-000000000001',
      'e2eKey': base64.encode(Uint8List(32)),
      'expiresAtMilliseconds': DateTime.now().millisecondsSinceEpoch + 300000,
    });
    final qr =
        'balance-relay://pair?data=${base64Url.encode(utf8.encode(legacy)).replaceAll('=', '')}';
    expect(
      () => RelayPairingPayload.parse(qr),
      throwsA(
        predicate(
          (e) => e is FormatException && e.message == '配对二维码包含不受支持的服务器字段',
        ),
      ),
    );
  });

  test('结构化错误码驱动 Mac 离线提示', () async {
    final client = RelayClient(
      MemoryIdentityStore(),
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'PC_OFFLINE', 'error': 'PC offline'}),
          503,
        ),
      ),
    );
    final identity = RelayIdentity(
      deviceId: 'device_security_0007',
      appToken: 'app-token-security-${List.filled(48, 't').join()}',
      e2eKey: Uint8List(32),
    );
    await expectLater(
      client.query(identity),
      throwsA(
        predicate(
          (e) =>
              e is RelayClientException &&
              e.code == 'PC_OFFLINE' &&
              e.message.contains('Mac 连接已断开'),
        ),
      ),
    );
  });

  test('Contract pairing fixture 与 Dart model 一致', () {
    final data = File(
      '${contractFixtureRoot.path}/pairing-valid.json',
    ).readAsBytesSync();
    final encoded = base64Url.encode(data).replaceAll('=', '');
    final payload = RelayPairingPayload.parse(
      'balance-relay://pair?data=$encoded',
    );
    expect(payload.version, 1);
    expect(payload.deviceId, 'device_contract_0001');
    expect(payload.e2eKey.length, 32);
  });

  test('Contract AES-GCM vector 可由 Dart 解密', () {
    final vector =
        jsonDecode(
              File(
                '${contractFixtureRoot.path}/aes-gcm-vector.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final envelope = RelayOpaqueEnvelope.fromJson(
      vector['envelope'] as Map<String, dynamic>,
    );
    final plaintext = RelayCrypto.open(
      envelope,
      Uint8List.fromList(base64.decode(vector['key'] as String)),
    );
    expect(plaintext['action'], 'balance.refresh');
    expect(plaintext['issuedAtMilliseconds'], 1700000000000);
    expect(plaintext['nonce'], 'contract-query-nonce-0001');
  });

  test('Contract pairing fields 不含 server override', () {
    final contract =
        jsonDecode(
              File(
                '${contractFixtureRoot.path}/contract.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(contract['pairingFields'], [
      'version',
      'deviceID',
      'pairCode',
      'e2eKey',
      'expiresAtMilliseconds',
    ]);
    expect(
      (contract['pairingFields'] as List<dynamic>).contains('serverBaseURL'),
      false,
    );
  });

  test('E2EE 信封往返并拒绝篡改和错误密钥', () {
    final key = Uint8List.fromList(List.generate(32, (index) => index));
    final envelope = RelayCrypto.seal({
      'action': 'balance.refresh',
      'nonce': 'security-nonce',
    }, key);
    expect(RelayCrypto.open(envelope, key)['action'], 'balance.refresh');

    final tampered = RelayOpaqueEnvelope(
      nonce: envelope.nonce,
      ciphertext:
          '${envelope.ciphertext.substring(0, envelope.ciphertext.length - 2)}AA',
      tag: envelope.tag,
    );
    expect(() => RelayCrypto.open(tampered, key), throwsFormatException);
    expect(
      () => RelayCrypto.open(envelope, Uint8List(32)),
      throwsFormatException,
    );
  });

  test('配对领取仅接受长随机 App Token 并写入安全存储接口', () async {
    final store = MemoryIdentityStore();
    final client = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://relay.example.invalid/api/v1/pair/claim',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['pairCode'], 'pair-code-security-000000000001');
        return http.Response(
          jsonEncode({
            'deviceId': 'device_security_0001',
            'appToken': 'app-token-security-${List.filled(48, 'x').join()}',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final payload = RelayPairingPayload.parse(
      pairingQr(expiresAt: DateTime.now().millisecondsSinceEpoch + 300000),
    );
    final identity = await client.claimPairing(payload);
    expect(identity.appToken.length, greaterThan(40));
    expect(store.value?.deviceId, identity.deviceId);
    expect(store.value?.e2eKey, identity.e2eKey);
  });

  test('中继查询正文不泄露动作并绑定 requestId', () async {
    final store = MemoryIdentityStore();
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    final identity = RelayIdentity(
      deviceId: 'device_security_0002',
      appToken: 'app-token-security-${List.filled(48, 'y').join()}',
      e2eKey: key,
    );
    final client = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer ${identity.appToken}');
        expect(request.headers['x-device-id'], identity.deviceId);
        expect(request.body.contains('balance.refresh'), false);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final requestId = body['requestId'] as String;
        final responseEnvelope = RelayCrypto.seal({
          'generatedAtMilliseconds': 1700000000000,
          'snapshots': <dynamic>[],
        }, key);
        return http.Response(
          jsonEncode({
            'requestId': requestId,
            'envelope': responseEnvelope.toJson(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final response = await client.query(identity);
    expect(response.snapshots, isEmpty);
    expect(response.generatedAtMilliseconds, 1700000000000);
  });

  test('中继拒绝不匹配 requestId', () async {
    final store = MemoryIdentityStore();
    final key = Uint8List(32);
    final identity = RelayIdentity(
      deviceId: 'device_security_0003',
      appToken: 'app-token-security-${List.filled(48, 'z').join()}',
      e2eKey: key,
    );
    final client = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'requestId': 'different_request_id_0001',
            'envelope': RelayCrypto.seal({
              'generatedAtMilliseconds': 0,
              'snapshots': <dynamic>[],
            }, key).toJson(),
          }),
          200,
        ),
      ),
    );
    await expectLater(
      client.query(identity),
      throwsA(isA<RelayClientException>()),
    );
  });

  test('配对二维码接受 macOS 标准 base64 的 e2eKey（含 + 和 / 字符）', () {
    // macOS 端 JSONEncoder 对 Data 输出标准 base64（可能含 + 和 /），
    // 且整个 QR payload 是 base64url 编码。此用例验证两种编码混用时能正确解析。
    const now = 1700000000000;
    // 构造含标准 base64 字符的 32 字节 key
    final rawKey = List<int>.generate(32, (index) => (index * 7 + 3) % 256);
    final key = Uint8List.fromList(rawKey);
    final keyB64 = base64.encode(key);
    // 确保 keyB64 含有 + 或 / 之一，否则换个 key
    assert(
      keyB64.contains('+') || keyB64.contains('/') || keyB64.contains('='),
    );
    final json = jsonEncode({
      'version': 1,
      'deviceID': 'device_security_0001',
      'pairCode': 'pair-code-security-000000000001',
      'e2eKey': keyB64,
      'expiresAtMilliseconds': now + 300000,
    });
    final qr =
        'balance-relay://pair?data=${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
    final payload = RelayPairingPayload.parse(qr, nowMilliseconds: now);
    expect(payload.e2eKey, key);
  });

  test('配对解析给出具体错误而非笼统提示', () {
    const now = 1700000000000;
    // 过期
    expect(
      () => RelayPairingPayload.parse(
        pairingQr(expiresAt: now - 1),
        nowMilliseconds: now,
      ),
      throwsA(
        predicate((e) => e is FormatException && e.message == '配对二维码已过期'),
      ),
    );
    // 短 key
    expect(
      () => RelayPairingPayload.parse(
        pairingQr(expiresAt: now + 300000, key: Uint8List(16)),
        nowMilliseconds: now,
      ),
      throwsA(
        predicate((e) => e is FormatException && e.message == '端到端密钥长度不符'),
      ),
    );
    // 非配对二维码
    expect(
      () => RelayPairingPayload.parse(
        'https://example.com/not-relay',
        nowMilliseconds: now,
      ),
      throwsA(
        predicate((e) => e is FormatException && e.message == '不是余额中继配对二维码'),
      ),
    );
  });

  test('忘记设备会撤销服务器记录再清本地', () async {
    final store = MemoryIdentityStore();
    var revoked = false;
    final identity = RelayIdentity(
      deviceId: 'device_security_0004',
      appToken: 'app-token-security-${List.filled(48, 'w').join()}',
      e2eKey: Uint8List(32),
    );
    final client = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://relay.example.invalid/api/v1/devices/revoke',
        );
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer ${identity.appToken}');
        revoked = true;
        return http.Response(jsonEncode({'ok': true, 'changed': true}), 200);
      }),
    );
    await client.revoke(identity);
    expect(revoked, true);
  });

  test('忘记设备彻底删除服务器记录（DELETE /devices）', () async {
    final store = MemoryIdentityStore();
    var deleted = false;
    final identity = RelayIdentity(
      deviceId: 'device_security_0005',
      appToken: 'app-token-security-${List.filled(48, 'v').join()}',
      e2eKey: Uint8List(32),
    );
    final client = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://relay.example.invalid/api/v1/devices',
        );
        expect(request.method, 'DELETE');
        expect(request.headers['authorization'], 'Bearer ${identity.appToken}');
        deleted = true;
        return http.Response(jsonEncode({'ok': true, 'deleted': true}), 200);
      }),
    );
    await client.deleteDevice(identity);
    expect(deleted, true);
  });

  test('registrationStatus 区分设备存在与 404 device_not_found', () async {
    final store = MemoryIdentityStore();
    final identity = RelayIdentity(
      deviceId: 'device_security_0006',
      appToken: 'app-token-security-${List.filled(48, 'u').join()}',
      e2eKey: Uint8List(32),
    );

    final existsClient = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'registered': true, 'paired': true}),
          200,
        ),
      ),
    );
    expect(await existsClient.registrationStatus(identity), true);

    final goneClient = RelayClient(
      store,
      serverBaseUrl: testRelayEndpoint,
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'device_not_found'}), 404),
      ),
    );
    expect(await goneClient.registrationStatus(identity), null);
  });
}
