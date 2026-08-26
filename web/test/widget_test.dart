import 'package:flutter_test/flutter_test.dart';
import 'package:relay_core/relay_core.dart';
import 'package:token_cost_terminal/controllers/terminal_session_controller.dart';
import 'package:token_cost_terminal/main.dart';
import 'package:token_cost_terminal/services/terminal_api.dart';
import 'package:token_cost_terminal/services/terminal_identity_persistence.dart';

void main() {
  testWidgets('shows secure pairing actions when no terminal is stored', (
    tester,
  ) async {
    final controller = TerminalSessionController(
      api: _FakeTerminalApi(),
      store: _MemoryStore(),
      autoPoll: false,
    );

    await tester.pumpWidget(TokenCostTerminalApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('A QUIET WINDOW\nINTO YOUR MAC.'), findsOneWidget);
    expect(find.text('OPEN CAMERA'), findsOneWidget);
    expect(find.text('PASTE LINK'), findsOneWidget);
  });
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
  @override
  Future<RelayIdentity> claimPairing(RelayPairingPayload payload) {
    throw UnimplementedError();
  }

  @override
  Future<RelayDeviceStatus> deviceStatus(RelayIdentity identity) {
    throw UnimplementedError();
  }

  @override
  Future<RelayTerminalInfo> revokeTerminal(RelayIdentity identity) {
    throw UnimplementedError();
  }
}
