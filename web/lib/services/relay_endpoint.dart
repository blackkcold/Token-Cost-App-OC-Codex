import 'package:flutter/foundation.dart';

abstract final class RelayEndpoint {
  static const String buildValue = String.fromEnvironment('RELAY_BASE_URL');

  static Uri requireConfigured({String? value}) {
    final raw = (value ?? buildValue).trim();
    if (raw.isEmpty) {
      throw StateError(
        'Build with --dart-define=RELAY_BASE_URL=https://relay.example',
      );
    }
    final uri = Uri.tryParse(raw);
    final validScheme = kReleaseMode
        ? uri?.scheme == 'https'
        : uri?.scheme == 'https' || uri?.scheme == 'http';
    if (uri == null ||
        !validScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        kReleaseMode
            ? 'RELAY_BASE_URL must be a valid HTTPS origin'
            : 'RELAY_BASE_URL must be a valid HTTP(S) origin',
      );
    }
    return uri.replace(path: uri.path == '/' ? '' : uri.path);
  }
}
