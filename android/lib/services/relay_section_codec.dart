import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/relay_models.dart';

class RelaySectionCodecException implements Exception {
  final String code;
  final String message;
  const RelaySectionCodecException(this.code, this.message);
  @override
  String toString() => message;
}

class RelaySectionCodec {
  static const int maxSectionBytes = 128 * 1024;
  static const int maxTotalBytes = 512 * 1024;

  static Future<Map<String, dynamic>> decodeAll(
    Map<String, dynamic>? encodedSections,
  ) async {
    if (encodedSections == null || encodedSections.isEmpty) return const {};
    final decoded = <String, dynamic>{};
    var total = 0;
    for (final entry in encodedSections.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const RelaySectionCodecException('INVALID_SECTION', 'Section envelope is invalid');
      }
      final section = RelayEncodedSection.fromJson(entry.value as Map<String, dynamic>);
      if (section.uncompressedBytes < 0 || section.uncompressedBytes > maxSectionBytes) {
        throw const RelaySectionCodecException('SECTION_TOO_LARGE', 'Section exceeds its plaintext limit');
      }
      final compressed = _decodeBase64(section.data);
      final bytes = switch (section.encoding) {
        'json+zlib' => await _boundedZlibDecode(compressed, maxSectionBytes),
        'json' => compressed,
        _ => throw const RelaySectionCodecException('INVALID_COMPRESSION', 'Unknown section encoding'),
      };
      if (bytes.length != section.uncompressedBytes) {
        throw const RelaySectionCodecException('INVALID_SECTION', 'Section size declaration is invalid');
      }
      total += bytes.length;
      if (total > maxTotalBytes) {
        throw const RelaySectionCodecException('SECTIONS_TOO_LARGE', 'Analytics sections exceed the total limit');
      }
      try {
        decoded[entry.key] = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const RelaySectionCodecException('INVALID_SECTION', 'Section JSON is invalid');
      }
    }
    return decoded;
  }

  static Uint8List _decodeBase64(String value) {
    try {
      return base64.decode(value);
    } catch (_) {
      throw const RelaySectionCodecException('INVALID_SECTION', 'Section Base64 is invalid');
    }
  }

  static Future<Uint8List> _boundedZlibDecode(Uint8List compressed, int limit) async {
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in ZLibCodec().decoder.bind(Stream.value(compressed))) {
        if (builder.length + chunk.length > limit) {
          throw const RelaySectionCodecException('DECOMPRESSION_LIMIT_EXCEEDED', 'Section decompression limit exceeded');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on RelaySectionCodecException {
      rethrow;
    } catch (_) {
      throw const RelaySectionCodecException('INVALID_COMPRESSION', 'Section decompression failed');
    }
  }
}
