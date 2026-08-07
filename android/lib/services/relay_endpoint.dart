import 'package:flutter/foundation.dart';

class RelayEndpoint {
  static const String buildValue = String.fromEnvironment('RELAY_BASE_URL');

  static Uri requireConfigured({String? value}) {
    final raw = (value ?? buildValue).trim();
    if (raw.isEmpty) {
      throw StateError('RELAY_BASE_URL is required');
    }
    final uri = Uri.tryParse(raw);
    final allowedScheme = kReleaseMode
        ? uri?.scheme == 'https'
        : uri?.scheme == 'https' || uri?.scheme == 'http';
    if (uri == null ||
        !allowedScheme ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        kReleaseMode
            ? 'RELAY_BASE_URL must be a valid HTTPS URL'
            : 'RELAY_BASE_URL must be a valid HTTP(S) URL',
      );
    }
    return uri;
  }
}
