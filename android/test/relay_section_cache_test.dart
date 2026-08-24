import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:balance_monitor/models/relay_models.dart';
import 'package:balance_monitor/services/relay_section_cache.dart';

class MemoryCacheKeyStore implements RelaySectionCacheKeyStore {
  Uint8List? value;
  @override
  Future<void> delete() async => value = null;
  @override
  Future<Uint8List?> load() async => value;
  @override
  Future<void> save(Uint8List key) async => value = key;
}

void main() {
  test('sections cache 加密、设备隔离并可删除', () async {
    final directory = await Directory.systemTemp.createTemp(
      'relay-section-cache-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final keyStore = MemoryCacheKeyStore();
    final cache = RelaySectionCache(
      keyStore: keyStore,
      directoryOverride: directory,
    );
    final response = RelayBalanceResponse(
      generatedAtMilliseconds: 1,
      requestNonce: 'cache-request-nonce-0001',
      snapshots: const [],
      sections: const {
        'overview': {'totalTokens': 1234.0},
      },
    );

    final beforeSave = DateTime.now().millisecondsSinceEpoch;
    await cache.save('device-cache-0001', response);
    final afterSave = DateTime.now().millisecondsSinceEpoch;

    final file = File('${directory.path}/relay-sections-v1.enc');
    final contents = utf8.decode(await file.readAsBytes());
    expect(contents.contains('totalTokens'), false);
    expect(contents.contains('1234'), false);
    final entry = await cache.load('device-cache-0001');
    expect(entry?.sections['overview'], {'totalTokens': 1234.0});
    expect(
      entry?.generatedAtMilliseconds,
      inInclusiveRange(beforeSave, afterSave),
    );
    expect(await cache.load('different-device'), isNull);
    await cache.delete();
    expect(await file.exists(), false);
    expect(keyStore.value, isNull);
  });
}
