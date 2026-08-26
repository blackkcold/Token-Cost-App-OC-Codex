import 'package:relay_core/relay_core.dart';

import 'terminal_identity_persistence.dart';

TerminalIdentityPersistence createTerminalIdentityStore(Uri relayEndpoint) =>
    _UnsupportedTerminalIdentityStore();

final class _UnsupportedTerminalIdentityStore
    implements TerminalIdentityPersistence {
  @override
  Future<void> delete() async {}

  @override
  Future<RelayIdentity?> load() async => null;

  @override
  Future<void> save(RelayIdentity identity) {
    throw UnsupportedError('Encrypted terminal storage requires a web browser');
  }
}
