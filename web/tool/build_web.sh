#!/usr/bin/env bash
set -euo pipefail

: "${RELAY_BASE_URL:?Set RELAY_BASE_URL to the production HTTPS Relay origin}"

RELAY_ORIGIN="$(python3 -c 'import sys, urllib.parse; u=urllib.parse.urlparse(sys.argv[1]); assert u.scheme == "https" and u.hostname and not u.username and not u.password and not u.query and not u.fragment; print(f"{u.scheme}://{u.netloc}")' "${RELAY_BASE_URL}")"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

"${FLUTTER_BIN}" build web \
  --csp \
  --no-web-resources-cdn \
  --no-wasm-dry-run \
  --dart-define="RELAY_BASE_URL=${RELAY_ORIGIN}" \
  "$@"

python3 -c 'from pathlib import Path; import sys; path=Path("build/web/index.html"); source=path.read_text(); old="connect-src '\''self'\'' https: http://localhost:* http://127.0.0.1:*;"; new=f"connect-src '\''self'\'' {sys.argv[1]};"; assert source.count(old) == 1; path.write_text(source.replace(old, new))' "${RELAY_ORIGIN}"
BUILD_HASH="$(python3 -c 'from pathlib import Path; import hashlib; print(hashlib.sha256(Path("build/web/main.dart.js").read_bytes()).hexdigest()[:16])')"
python3 -c 'from pathlib import Path; import sys; path=Path("build/web/terminal_service_worker.js"); source=path.read_text(); assert source.count("__BUILD_HASH__") == 1; path.write_text(source.replace("__BUILD_HASH__", sys.argv[1]))' "${BUILD_HASH}"
python3 -c 'from pathlib import Path; import sys; source=Path("tool/security_headers.template").read_text(); Path("build/web/_headers").write_text(source.replace("__RELAY_ORIGIN__", sys.argv[1]))' "${RELAY_ORIGIN}"

if grep -R -E "__(RELAY_ORIGIN|BUILD_HASH)__" build/web >/dev/null 2>&1; then
  printf '%s\n' 'Unresolved build placeholder in build output' >&2
  exit 1
fi
