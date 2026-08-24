import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/relay_models.dart';
import 'relay_crypto.dart';

abstract interface class RelaySectionCacheKeyStore {
  Future<Uint8List?> load();
  Future<void> save(Uint8List key);
  Future<void> delete();
}

class SecureRelaySectionCacheKeyStore implements RelaySectionCacheKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyName = 'balance_relay_sections_cache_key_v1';

  @override
  Future<Uint8List?> load() async {
    final raw = await _storage.read(key: _keyName);
    if (raw == null) return null;
    try {
      final key = Uint8List.fromList(base64.decode(raw));
      return key.length == 32 ? key : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List key) =>
      _storage.write(key: _keyName, value: base64.encode(key));

  @override
  Future<void> delete() => _storage.delete(key: _keyName);
}

class RelaySectionCacheEntry {
  final int generatedAtMilliseconds;
  final Map<String, dynamic> sections;

  const RelaySectionCacheEntry({
    required this.generatedAtMilliseconds,
    required this.sections,
  });
}

class RelaySectionCache {
  static const ttl = Duration(minutes: 5);
  static const _fileName = 'relay-sections-v1.enc';
  final RelaySectionCacheKeyStore keyStore;
  final Directory? directoryOverride;
  Future<Uint8List>? _keyLoadInFlight;

  RelaySectionCache({
    RelaySectionCacheKeyStore? keyStore,
    this.directoryOverride,
  }) : keyStore = keyStore ?? SecureRelaySectionCacheKeyStore();

  Future<RelaySectionCacheEntry?> load(String deviceId) async {
    final file = await _file();
    if (!await file.exists()) return null;
    final key = await keyStore.load();
    if (key == null) return null;
    try {
      final envelopeJson =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final plaintext = RelayCrypto.open(
        RelayOpaqueEnvelope.fromJson(envelopeJson),
        key,
      );
      if (plaintext['deviceId'] != deviceId) return null;
      final generated =
          (plaintext['generatedAtMilliseconds'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - generated;
      if (age < 0 || age > ttl.inMilliseconds) {
        await delete();
        return null;
      }
      final sections = plaintext['sections'];
      if (sections is! Map<String, dynamic>) return null;
      return RelaySectionCacheEntry(
        generatedAtMilliseconds: generated,
        sections: sections,
      );
    } catch (_) {
      await delete();
      return null;
    }
  }

  Future<void> save(String deviceId, RelayBalanceResponse response) async {
    if (response.sections.isEmpty || response.error != null) return;
    final key = await _loadOrCreateKey();
    final envelope = RelayCrypto.seal({
      'version': 1,
      'deviceId': deviceId,
      'generatedAtMilliseconds': DateTime.now().millisecondsSinceEpoch,
      'sections': response.sections,
    }, key);
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(envelope.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await keyStore.delete();
  }

  Future<Uint8List> _loadOrCreateKey() async {
    final inFlight = _keyLoadInFlight;
    if (inFlight != null) return inFlight;
    final future = _createKeyIfNeeded();
    _keyLoadInFlight = future;
    return future;
  }

  Future<Uint8List> _createKeyIfNeeded() async {
    try {
      final existing = await keyStore.load();
      if (existing != null && existing.length == 32) return existing;
      final random = Random.secure();
      final key = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      await keyStore.save(key);
      final after = await keyStore.load();
      return after != null && after.length == 32 ? after : key;
    } finally {
      _keyLoadInFlight = null;
    }
  }

  Future<File> _file() async {
    final directory =
        directoryOverride ?? await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }
}
