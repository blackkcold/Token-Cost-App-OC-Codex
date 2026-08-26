import 'package:flutter_test/flutter_test.dart';
import 'package:token_cost_terminal/services/relay_endpoint.dart';

void main() {
  test('requires an explicit Relay endpoint', () {
    expect(() => RelayEndpoint.requireConfigured(value: ''), throwsStateError);
  });

  test('rejects credentials, query, and fragment overrides', () {
    expect(
      () => RelayEndpoint.requireConfigured(value: 'https://user@example.com'),
      throwsStateError,
    );
    expect(
      () =>
          RelayEndpoint.requireConfigured(value: 'https://relay.example/?x=1'),
      throwsStateError,
    );
    expect(
      () => RelayEndpoint.requireConfigured(value: 'https://relay.example/#x'),
      throwsStateError,
    );
  });

  test('accepts a configured HTTPS origin', () {
    expect(
      RelayEndpoint.requireConfigured(value: 'https://relay.example').origin,
      'https://relay.example',
    );
  });
}
