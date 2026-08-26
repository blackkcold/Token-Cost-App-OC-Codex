import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_core/relay_core.dart';
import 'package:token_cost_terminal/controllers/terminal_session_controller.dart';
import 'package:token_cost_terminal/services/terminal_api.dart';
import 'package:token_cost_terminal/services/terminal_identity_persistence.dart';

void main() {
  test('claim stays pending until Relay reports Mac activation', () async {
    final api = _FakeTerminalApi();
    final store = _MemoryStore();
    final controller = TerminalSessionController(
      api: api,
      store: store,
      autoPoll: false,
    );
    await controller.initialize();

    await controller.pairFromRawValue(_pairingUri());
    expect(controller.identity?.terminalState, RelayTerminalState.pending);
    expect(store.value?.keyVersion, 2);

    api.state = RelayTerminalState.active;
    await controller.refreshStatus();
    expect(controller.identity?.terminalState, RelayTerminalState.active);

    await controller.revokeTerminal();
    expect(controller.identity?.terminalState, RelayTerminalState.revoked);
  });

  test('invalid pairing input stays unpaired and reports error', () async {
    final controller = TerminalSessionController(
      api: _FakeTerminalApi(),
      store: _MemoryStore(),
      autoPoll: false,
    );
    await controller.initialize();
    await controller.pairFromRawValue('https://example.com/not-a-pairing-code');

    expect(controller.phase, TerminalSessionPhase.unpaired);
    expect(
      controller.errorMessage,
      'The pairing code is invalid, unsupported, or expired.',
    );
  });
}

String _pairingUri() {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'deviceID': 'device_contract_0001',
            'keyVersion': 2,
            'pairCode': 'pair-code-contract-000000000001',
            'e2eKey': base64.encode(Uint8List(32)..fillRange(0, 32, 66)),
            'expiresAtMilliseconds': 4102444800000,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'balance-relay://pair?data=$payload';
}

final class _MemoryStore implements TerminalIdentityPersistence {
  RelayIdentity? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<RelayIdentity?> load() async => value;

  @override
  Future<void> save(RelayIdentity identity) async => value = identity;
}

final class _FakeTerminalApi implements TerminalApi {
  RelayTerminalState state = RelayTerminalState.pending;

  @override
  Future<RelayIdentity> claimPairing(RelayPairingPayload payload) async =>
      RelayIdentity(
        deviceId: payload.deviceId,
        appToken: 'a' * 48,
        e2eKey: payload.e2eKey,
        keyVersion: payload.keyVersion,
        terminalState: RelayTerminalState.pending,
      );

  @override
  Future<RelayDeviceStatus> deviceStatus(RelayIdentity identity) async =>
      RelayDeviceStatus(
        deviceId: identity.deviceId,
        online: true,
        appOnline: true,
        appLastSeenAt: DateTime.now().millisecondsSinceEpoch,
        terminal: RelayTerminalInfo(
          keyVersion: identity.keyVersion,
          state: state,
          expiresAt: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
        ),
      );

  @override
  Future<RelayTerminalInfo> revokeTerminal(RelayIdentity identity) async =>
      RelayTerminalInfo(
        keyVersion: identity.keyVersion,
        state: RelayTerminalState.revoked,
      );
}
