@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_core/relay_core.dart';
import 'package:token_cost_terminal/services/terminal_identity_store_web.dart';

void main() {
  final endpoint = Uri.parse('https://relay.test');
  late WebTerminalIdentityStore store;

  setUp(() async {
    store = WebTerminalIdentityStore(endpoint);
    await store.delete();
  });

  tearDown(() => store.delete());

  test(
    'encrypts, binds, and deletes the terminal identity in IndexedDB',
    () async {
      final identity = RelayIdentity(
        deviceId: 'device_web_store_0001',
        appToken: 'a' * 48,
        e2eKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
        keyVersion: 3,
        terminalState: RelayTerminalState.active,
      );

      await store.save(identity);

      final restored = await store.load();
      expect(restored?.deviceId, identity.deviceId);
      expect(restored?.appToken, identity.appToken);
      expect(restored?.e2eKey, orderedEquals(identity.e2eKey));
      expect(restored?.keyVersion, identity.keyVersion);
      expect(restored?.terminalState, identity.terminalState);

      final otherOriginStore = WebTerminalIdentityStore(
        Uri.parse('https://other-relay.test'),
      );
      expect(await otherOriginStore.load(), isNull);

      await store.delete();
      expect(await store.load(), isNull);
    },
  );
}
