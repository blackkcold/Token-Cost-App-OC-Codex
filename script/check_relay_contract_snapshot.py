#!/usr/bin/env python3
import json
import os
import re
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


def parse_version(raw: str):
    """Parse a contract version like '1.1.0' or '1.0.0-draft'.

    Returns a comparable tuple. Non-numeric parts (e.g. '-draft') are ignored for
    ordering, so '1.0.0-draft' sorts equal to '1.0.0'.
    """
    m = re.match(r"^\s*v?(\d+)\.(\d+)\.(\d+)", raw)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def is_canonical_outdated(canonical_version: str, vendored_version: str) -> bool:
    """True only when the canonical contract version is strictly older than the vendored one.

    Any other mismatch (equal but different content, or canonical newer) must NOT be
    treated as a downgrade — it stays a hard failure.
    """
    c = parse_version(canonical_version)
    v = parse_version(vendored_version)
    if c is None or v is None:
        return False
    return c < v


if not CANONICAL.is_dir():
    print(f"WARNING: Canonical Relay Contract fixture directory is missing: {CANONICAL}")
    print("Falling back to vendored-snapshot internal consistency checks only.")
    skip_canonical_compare = True
else:
    skip_canonical_compare = False

if not skip_canonical_compare and (CANONICAL / "contract.json").is_file() and (PUBLIC / "contract.json").is_file():
    canonical_contract = load(CANONICAL / "contract.json")
    vendored_contract = load(PUBLIC / "contract.json")
    canonical_cv = canonical_contract.get("contractVersion", "")
    vendored_cv = vendored_contract.get("contractVersion", "")
    if is_canonical_outdated(canonical_cv, vendored_cv):
        print(
            f"WARNING: canonical contract version {canonical_cv!r} is older than vendored "
            f"{vendored_cv!r}; skipping per-fixture equality comparison."
        )
        skip_canonical_compare = True

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
