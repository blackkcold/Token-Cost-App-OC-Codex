#!/usr/bin/env python3
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "Resources" / "RelayContract" / "v1"
CANONICAL = Path(
    os.environ.get(
        "RELAY_CONTRACT_ROOT",
        ROOT.parent / "Token-Cost-Relay-Contract" / "test-vectors",
    )
)


def load(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


required = (
    "contract.json",
    "pairing-valid.json",
    "aes-gcm-vector.json",
    "request-v1.1.json",
    "response-v1.1.json",
    "section-zlib-vector.json",
)


if not CANONICAL.is_dir():
    print(f"WARNING: Canonical Relay Contract fixture directory is missing: {CANONICAL}")
    print("Falling back to vendored-snapshot internal consistency checks only.")
    skip_canonical_compare = True
else:
    skip_canonical_compare = False

for name in required:
    public_path = PUBLIC / name
    canonical_path = CANONICAL / name
    if not public_path.is_file():
        raise SystemExit(f"Vendored Relay contract fixture is missing: {name}")
    if not skip_canonical_compare:
        if not canonical_path.is_file():
            raise SystemExit(f"Canonical Relay contract fixture is missing: {name}")
        public_value = load(PUBLIC / name)
        canonical_value = load(canonical_path)
        if public_value != canonical_value:
            raise SystemExit(f"Relay contract snapshot mismatch: {name}")

contract = load(PUBLIC / "contract.json")
if contract.get("protocolVersion") != 1:
    raise SystemExit("Relay protocolVersion must be 1")
if contract.get("contractVersion") != "1.1.0":
    raise SystemExit("Relay contractVersion must be 1.1.0")
if "serverBaseURL" in contract.get("pairingFields", []):
    raise SystemExit("serverBaseURL must not appear in pairingFields")

if skip_canonical_compare:
    print(f"Relay contract snapshot: PASS (canonical compare skipped, vendored self-check only)")
else:
    print(f"Relay contract snapshot: PASS ({CANONICAL})")
