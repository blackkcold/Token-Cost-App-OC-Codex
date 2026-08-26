import 'package:relay_core/relay_core.dart';

abstract interface class TerminalIdentityPersistence {
  Future<void> save(RelayIdentity identity);
  Future<RelayIdentity?> load();
  Future<void> delete();
}
