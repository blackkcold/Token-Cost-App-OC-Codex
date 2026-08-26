import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'models.dart';

class RelayCrypto {
  static final Random _random = Random.secure();

  static String randomId([int bytes = 18]) {
    if (bytes < 1) throw ArgumentError.value(bytes, 'bytes', 'must be positive');
    final data = Uint8List.fromList(List.generate(bytes, (_) => _random.nextInt(256)));
    return base64Url.encode(data).replaceAll('=', '');
  }

  static RelayOpaqueEnvelope seal(Map<String, dynamic> value, Uint8List key) {
    if (key.length != 32) throw const FormatException('E2EE 密钥长度无效');
    final nonce = Uint8List.fromList(List.generate(12, (_) => _random.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    final offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    final length = offset + cipher.doFinal(output, offset);
    final combined = Uint8List.sublistView(output, 0, length);
    if (combined.length < 17) throw const FormatException('E2EE 加密结果无效');
    return RelayOpaqueEnvelope(
      nonce: base64.encode(nonce),
      ciphertext: base64.encode(Uint8List.sublistView(combined, 0, combined.length - 16)),
      tag: base64.encode(Uint8List.sublistView(combined, combined.length - 16)),
    );
  }

  static Map<String, dynamic> open(RelayOpaqueEnvelope envelope, Uint8List key) {
    if (key.length != 32) throw const FormatException('E2EE 密钥长度无效');
    late Uint8List nonce;
    late Uint8List ciphertext;
    late Uint8List tag;
    try {
      nonce = Uint8List.fromList(base64.decode(envelope.nonce));
      ciphertext = Uint8List.fromList(base64.decode(envelope.ciphertext));
      tag = Uint8List.fromList(base64.decode(envelope.tag));
    } catch (_) {
      throw const FormatException('E2EE 信封 Base64 无效');
    }
    if (nonce.length != 12 || ciphertext.isEmpty || tag.length != 16) {
      throw const FormatException('E2EE 信封字段无效');
    }
    final combined = Uint8List(ciphertext.length + tag.length)
      ..setAll(0, ciphertext)
      ..setAll(ciphertext.length, tag);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final output = Uint8List(cipher.getOutputSize(combined.length));
    final offset = cipher.processBytes(combined, 0, combined.length, output, 0);
    try {
      final length = offset + cipher.doFinal(output, offset);
      final decoded = jsonDecode(utf8.decode(Uint8List.sublistView(output, 0, length)));
      if (decoded is! Map<String, dynamic>) throw const FormatException('E2EE 明文必须是 JSON object');
      return decoded;
    } on InvalidCipherTextException {
      throw const FormatException('E2EE 认证失败：密文被篡改或密钥不匹配');
    }
  }
}
