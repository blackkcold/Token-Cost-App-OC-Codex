import 'package:relay_core/relay_core.dart';

abstract interface class TerminalApi {
  Future<RelayIdentity> claimPairing(RelayPairingPayload payload);
  Future<RelayDeviceStatus> deviceStatus(RelayIdentity identity);
  Future<RelayTerminalInfo> revokeTerminal(RelayIdentity identity);
}

final class RelayTerminalApi implements TerminalApi {
  RelayTerminalApi(Uri endpoint)
    : _client = RelayApiClient(serverBaseUrl: endpoint);

  final RelayApiClient _client;

  @override
  Future<RelayIdentity> claimPairing(RelayPairingPayload payload) =>
      _client.claimPairing(payload, clientKind: 'web');

  @override
  Future<RelayDeviceStatus> deviceStatus(RelayIdentity identity) =>
      _client.deviceStatus(identity);

  @override
  Future<RelayTerminalInfo> revokeTerminal(RelayIdentity identity) =>
      _client.revokeTerminal(identity);
}
