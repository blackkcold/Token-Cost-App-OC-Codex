import 'dart:convert';
import 'dart:typed_data';

import 'package:relay_core/relay_core.dart';
import 'package:test/test.dart';

String pairingQr({int keyVersion = 2, int expiresAt = 4102444800000}) {
  final payload = jsonEncode({
    'version': 1,
    'deviceID': 'device_contract_0001',
    'keyVersion': keyVersion,
    'pairCode': 'pair-code-contract-000000000001',
    'e2eKey': base64.encode(Uint8List.fromList(List.filled(32, 0x42))),
    'expiresAtMilliseconds': expiresAt,
  });
  return 'balance-relay://pair?data=${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
}

void main() {
  test(
      'pairing payload requires a positive key version and rejects unknown fields',
      () {
    final payload =
        RelayPairingPayload.parse(pairingQr(), nowMilliseconds: 1700000000000);
    expect(payload.keyVersion, 2);
    expect(payload.e2eKey, hasLength(32));
    expect(
      () => RelayPairingPayload.parse(pairingQr(keyVersion: 0),
          nowMilliseconds: 1700000000000),
      throwsFormatException,
    );
  });

  test('pairing URI rejects extra fields, duplicate data, paths, and fragments',
      () {
    final qr = pairingQr();

    for (final invalid in [
      '$qr&serverBaseURL=https%3A%2F%2Fevil.example',
      '$qr&data=duplicate',
      qr.replaceFirst('pair?', 'pair/extra?'),
      '$qr#ignored',
    ]) {
      expect(
        () => RelayPairingPayload.parse(
          invalid,
          nowMilliseconds: 1700000000000,
        ),
        throwsFormatException,
      );
    }
  });

  test('AES-256-GCM round trip binds ciphertext authentication', () {
    final key = Uint8List.fromList(List.generate(32, (index) => index));
    final envelope =
        RelayCrypto.seal({'keyVersion': 2, 'action': 'balance.refresh'}, key);
    expect(RelayCrypto.open(envelope, key)['keyVersion'], 2);
    expect(
      () => RelayCrypto.open(
        RelayOpaqueEnvelope(
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          tag: '${envelope.tag.substring(0, envelope.tag.length - 2)}AA',
        ),
        key,
      ),
      throwsFormatException,
    );
  });
}
