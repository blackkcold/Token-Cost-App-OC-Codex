#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "Resources" / "RelayContract" / "v1"
PRIVATE = ROOT / "relay" / "test" / "fixtures" / "relay-contract-v1"


def load(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


for name in ("contract.json", "pairing-valid.json", "aes-gcm-vector.json"):
    public_value = load(PUBLIC / name)
    private_path = PRIVATE / name
    if private_path.exists():
        private_value = load(private_path)
        if public_value != private_value:
            raise SystemExit(f"Relay contract snapshot mismatch: {name}")

contract = load(PUBLIC / "contract.json")
if contract.get("protocolVersion") != 1:
    raise SystemExit("Relay protocolVersion must be 1")
if "serverBaseURL" in contract.get("pairingFields", []):
    raise SystemExit("serverBaseURL must not appear in pairingFields")

print("Relay contract snapshot: PASS")
