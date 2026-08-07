#!/usr/bin/env python3
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
tracked = subprocess.run(
    ["git", "ls-files", "-z"],
    cwd=ROOT,
    check=True,
    capture_output=True,
).stdout.decode().split("\0")
tracked = [path for path in tracked if path]

forbidden_paths = (
    "relay/",
    ".codex/",
    ".sisyphus/",
    ".playwright-mcp/",
)
forbidden_names = (
    ".env",
    "key.properties",
    "local.properties",
)
forbidden_suffixes = (".jks", ".keystore", ".p12", ".mobileprovision")

violations: list[str] = []
for relative in tracked:
    if relative.startswith(forbidden_paths):
        violations.append(f"forbidden tracked path: {relative}")
    name = Path(relative).name
    if name in forbidden_names or name.endswith(forbidden_suffixes):
        violations.append(f"forbidden tracked secret file: {relative}")

absolute_path = re.compile(
    r"(?:/Users/|C:\\\\Users\\\\)(?=[A-Za-z0-9._-])[^\s`\"']+"
)
for relative in tracked:
    path = ROOT / relative
    if not path.is_file() or path.stat().st_size > 1_000_000:
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if absolute_path.search(content):
        violations.append(f"absolute personal path in tracked text: {relative}")

if violations:
    raise SystemExit("\n".join(violations))

print("Public repository boundary: PASS")
