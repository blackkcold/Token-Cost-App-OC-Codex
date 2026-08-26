import 'terminal_identity_persistence.dart';
import 'terminal_identity_store_stub.dart'
    if (dart.library.js_interop) 'terminal_identity_store_web.dart'
    as platform;

export 'terminal_identity_persistence.dart';

TerminalIdentityPersistence createTerminalIdentityStore(Uri relayEndpoint) =>
    platform.createTerminalIdentityStore(relayEndpoint);
