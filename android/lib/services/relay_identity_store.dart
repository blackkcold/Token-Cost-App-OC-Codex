import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/relay_models.dart';

abstract interface class RelayIdentityPersistence {
  Future<void> save(RelayIdentity identity);
  Future<RelayIdentity?> load();
  Future<void> delete();
}

class RelayIdentityStore implements RelayIdentityPersistence {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'balance_relay_identity_v1';
  final Uri expectedServerBaseUrl;

  RelayIdentityStore({required this.expectedServerBaseUrl});

  @override
  Future<void> save(RelayIdentity identity) async {
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'serverBaseUrl': expectedServerBaseUrl.toString(),
        'deviceId': identity.deviceId,
        'appToken': identity.appToken,
        'e2eKey': base64.encode(identity.e2eKey),
      }),
    );
  }

  @override
  Future<RelayIdentity?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final storedServer = Uri.parse(json['serverBaseUrl'] as String);
      final key = Uint8List.fromList(base64.decode(json['e2eKey'] as String));
      if (_normalized(storedServer) != _normalized(expectedServerBaseUrl) ||
          key.length != 32) {
        return null;
      }
      return RelayIdentity(
        deviceId: json['deviceId'] as String,
        appToken: json['appToken'] as String,
        e2eKey: key,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);

  static String _normalized(Uri uri) {
    final value = uri.toString();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
