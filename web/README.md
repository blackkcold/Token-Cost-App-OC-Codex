# Token Cost Terminal PWA

Flutter Web terminal for the optional Token Cost Relay. It shares platform-neutral pairing, API and AES-256-GCM primitives with Android through `packages/relay_core`.

## Security model

- The Relay endpoint is fixed at build time and must use HTTPS outside local development.
- Pairing QR data never carries an endpoint override.
- Contract 1.2 binds the App token, E2EE key, request/response and terminal session to the same positive `keyVersion`.
- A claimed terminal remains `PENDING` and cannot query until the Mac activates it.
- Browser credentials are encrypted at rest with a versioned local record; logout/revoke clears the local terminal state.
- CSP and the Service Worker restrict caching to same-origin static resources. Relay API responses, credentials and terminal records are never cached by the Service Worker.

## Validation

```bash
flutter pub get
flutter analyze
flutter test test/relay_endpoint_test.dart \
  test/terminal_session_controller_test.dart \
  test/widget_test.dart

PATH="/path/to/flutter/bin:$PATH" \
RELAY_BASE_URL="https://relay.example.invalid" \
bash tool/build_web.sh
```

Browser-runtime storage tests are separate from the CI-safe non-browser suite above.
