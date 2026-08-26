import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:relay_core/relay_core.dart';
import 'package:web/web.dart' as web;

import 'terminal_identity_persistence.dart';

TerminalIdentityPersistence createTerminalIdentityStore(Uri relayEndpoint) =>
    WebTerminalIdentityStore(relayEndpoint);

final class WebTerminalIdentityStore implements TerminalIdentityPersistence {
  WebTerminalIdentityStore(this.relayEndpoint);

  static const _databaseName = 'token_cost_terminal';
  static const _objectStoreName = 'secure_terminal';
  static const _cryptoKeyRecord = 'wrapping_key_v1';
  static const _identityRecord = 'relay_identity_v1';
  static const _identityRecordVersion = 2;

  final Uri relayEndpoint;

  @override
  Future<void> save(RelayIdentity identity) async {
    final database = await _openDatabase();
    try {
      final key = await _loadOrCreateKey(database);
      final iv = Uint8List(12);
      web.window.crypto.getRandomValues(iv.toJS);
      final plaintext = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'serverBaseUrl': _normalizedEndpoint,
            'deviceId': identity.deviceId,
            'appToken': identity.appToken,
            'e2eKey': base64.encode(identity.e2eKey),
            'keyVersion': identity.keyVersion,
            'terminalState': identity.terminalState.wireValue,
          }),
        ),
      );
      final encrypted = await web.window.crypto.subtle
          .encrypt(_aesGcmParameters(iv), key, plaintext.toJS)
          .toDart;
      final encryptedBytes = Uint8List.view(
        (encrypted as JSArrayBuffer).toDart,
      );
      final record = jsonEncode({
        'version': _identityRecordVersion,
        'serverBaseUrl': _normalizedEndpoint,
        'iv': base64.encode(iv),
        'ciphertext': base64.encode(encryptedBytes),
      });
      await _put(database, _identityRecord, record.toJS);
    } finally {
      database.close();
    }
  }

  @override
  Future<RelayIdentity?> load() async {
    final database = await _openDatabase();
    try {
      final keyValue = await _get(database, _cryptoKeyRecord);
      final recordValue = await _get(database, _identityRecord);
      final keyMissing = keyValue == null || keyValue.isUndefinedOrNull;
      final recordMissing =
          recordValue == null || recordValue.isUndefinedOrNull;
      if (keyMissing && recordMissing) {
        return null;
      }
      if (keyMissing || recordMissing) {
        throw StateError('Secure terminal storage is incomplete');
      }
      final key = keyValue as web.CryptoKey;
      final record = jsonDecode((recordValue as JSString).toDart);
      if (record is! Map<String, dynamic>) {
        throw StateError('Secure terminal storage has an invalid record');
      }
      if (record['version'] == 1) {
        return null;
      }
      if (record['version'] != _identityRecordVersion) {
        throw StateError('Secure terminal storage version is unsupported');
      }
      if (record['serverBaseUrl'] != _normalizedEndpoint) return null;
      final iv = Uint8List.fromList(base64.decode(record['iv'] as String));
      final ciphertext = Uint8List.fromList(
        base64.decode(record['ciphertext'] as String),
      );
      if (iv.length != 12 || ciphertext.length < 17) return null;
      final decrypted = await web.window.crypto.subtle
          .decrypt(_aesGcmParameters(iv), key, ciphertext.toJS)
          .toDart;
      final decoded = jsonDecode(
        utf8.decode(Uint8List.view((decrypted as JSArrayBuffer).toDart)),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['serverBaseUrl'] != _normalizedEndpoint) {
        return null;
      }
      final e2eKey = Uint8List.fromList(
        base64.decode(decoded['e2eKey'] as String),
      );
      final appToken = decoded['appToken'];
      final deviceId = decoded['deviceId'];
      final keyVersion = decoded['keyVersion'];
      if (e2eKey.length != 32 ||
          appToken is! String ||
          appToken.length < 40 ||
          deviceId is! String ||
          keyVersion is! int ||
          keyVersion < 1) {
        return null;
      }
      return RelayIdentity(
        deviceId: deviceId,
        appToken: appToken,
        e2eKey: e2eKey,
        keyVersion: keyVersion,
        terminalState: RelayTerminalState.parse(decoded['terminalState']),
      );
    } on StateError {
      rethrow;
    } on Object {
      throw StateError('Stored terminal identity could not be verified');
    } finally {
      database.close();
    }
  }

  @override
  Future<void> delete() async {
    final database = await _openDatabase();
    try {
      final transaction = database.transaction(
        _objectStoreName.toJS,
        'readwrite',
      );
      final completion = _transactionCompleted(transaction);
      final request = transaction.objectStore(_objectStoreName).clear();
      await _requestResult(request);
      await completion;
    } finally {
      database.close();
    }
  }

  String get _normalizedEndpoint {
    final value = relayEndpoint.toString();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  JSAny _aesGcmParameters(Uint8List iv) => <String, Object>{
    'name': 'AES-GCM',
    'iv': iv.toJS,
    'additionalData': Uint8List.fromList(
      utf8.encode('token-cost-terminal|$_normalizedEndpoint'),
    ).toJS,
    'tagLength': 128,
  }.jsify()!;

  Future<web.CryptoKey> _loadOrCreateKey(web.IDBDatabase database) async {
    final existing = await _get(database, _cryptoKeyRecord);
    if (existing != null && !existing.isUndefinedOrNull) {
      return existing as web.CryptoKey;
    }
    final generated = await web.window.crypto.subtle
        .generateKey(
          <String, Object>{'name': 'AES-GCM', 'length': 256}.jsify()!,
          false,
          <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart;
    final key = generated as web.CryptoKey;
    await _put(database, _cryptoKeyRecord, key);
    return key;
  }

  Future<web.IDBDatabase> _openDatabase() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_objectStoreName)) {
        database.createObjectStore(_objectStoreName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.complete(request.result as web.IDBDatabase);
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'Unable to open IndexedDB'),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<JSAny?> _get(web.IDBDatabase database, String key) {
    final transaction = database.transaction(_objectStoreName.toJS, 'readonly');
    return _requestResult(
      transaction.objectStore(_objectStoreName).get(key.toJS),
    );
  }

  Future<void> _put(web.IDBDatabase database, String key, JSAny value) async {
    final transaction = database.transaction(
      _objectStoreName.toJS,
      'readwrite',
    );
    final completion = _transactionCompleted(transaction);
    await _requestResult(
      transaction.objectStore(_objectStoreName).put(value, key.toJS),
    );
    await completion;
  }

  Future<JSAny?> _requestResult(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB request failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<void> _transactionCompleted(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    transaction.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            transaction.error?.message ?? 'IndexedDB transaction failed',
          ),
        );
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            transaction.error?.message ?? 'IndexedDB transaction aborted',
          ),
        );
      }
    }).toJS;
    return completer.future;
  }
}
