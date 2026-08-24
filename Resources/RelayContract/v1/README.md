# Relay Contract v1 Snapshot

This directory is the Public App's vendored, offline test snapshot of the Client-facing Relay Contract.

- `contract.json`: protocol fields, device routes, WebSocket frame names and stable error codes
- `pairing-valid.json`: pairing payload without any server endpoint
- `aes-gcm-vector.json`: deterministic test-only AES-256-GCM vector
- `request-v1.1.json` / `response-v1.1.json`: analytics request and nonce-bound response vectors
- `section-zlib-vector.json`: RFC 1950 zlib interoperability vector

The canonical Public Contract will live in the separate `Token-Cost-Relay-Contract` repository. Public App builds must not fetch the Private Relay or Contract repository at build time. Update this snapshot only together with Swift, Dart and Node compatibility tests.

The deterministic key and nonce in the vector are test data only and must never be used in production.
