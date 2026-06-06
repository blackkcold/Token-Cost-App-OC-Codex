#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/developer_mode_sources.manifest"
ALLOWLIST="$SCRIPT_DIR/developer_mode_banned_symbols_allowlist.json"

# ─── Category definitions ───────────────────────────────────────────────
CAT1_NAME="Category 1 - Content read APIs"
CAT1_SYMBOLS="Data(contentsOf: String(contentsOf: FileHandle(forReadingAtPath: read( pread( mmap( JSONDecoder JSONSerialization sqlite3_open sqlite3_open_v2"

CAT2_NAME="Category 2 - ObjC bridge content read APIs"
CAT2_SYMBOLS="NSData(contentsOf: NSData(contentsOfFile: NSString(contentsOfFile: NSString(contentsOf: NSDictionary(contentsOf: NSArray(contentsOf: InputStream(url: FileManager.default.contents(atPath:"

CAT3_NAME="Category 3 - Transitive content read entries"
CAT3_SYMBOLS="OpenCodeSkillDiscovery OpenCodeSkillsReadOnlyStore SourceDiscoveryService TokenDatabaseClient SafeFileStore.readCodable OpenCodeSkillsModel.refresh CodexSessionCollector"

CAT4_NAME="Category 4 - Credential chain entries"
CAT4_SYMBOLS="BalanceManager BrowserCookieExtractor SecureCredentialStore.discoverCredentials AuthTokenProvider openCodeAuthURL codexAuthURL SecureCredentialStore.saveWorkspaceID SecureCredentialStore.deleteWorkspaceID"

CAT5_NAME="Category 5 - Network/process entries"
CAT5_SYMBOLS="URLSession Process NSWorkspace.open UpdateChecker OpenCodeGoDashboardFetcher"

CAT6_NAME="Category 6 - Environment credential read"
CAT6_SYMBOLS="ProcessInfo.processInfo.environment"

CAT7_NAME="Category 7 - Direct file APIs"
CAT7_SYMBOLS="FileManager.default.contentsOfDirectory FileManager.default.attributesOfItem"

# ─── Check manifest exists ──────────────────────────────────────────────
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest file not found: $MANIFEST"
    exit 1
fi

# ─── Read manifest, skip comments and empty lines ───────────────────────
files=()
while IFS= read -r line; do
    # Trim leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$line" ]]; then
        continue
    fi
    case "$line" in
        \#*) continue ;;
    esac
    files+=("$line")
done < "$MANIFEST"

if [[ ${#files[@]} -eq 0 ]]; then
    echo "ERROR: Manifest is empty (no source files listed)"
    exit 1
fi

# ─── Verify all files exist ─────────────────────────────────────────────
for f in "${files[@]}"; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
        echo "ERROR: File listed in manifest does not exist: $f"
        exit 1
    fi
done

# ─── Parse allowlist into temp file ─────────────────────────────────────
allowlist_lookup="$(mktemp)"
trap 'rm -f "$allowlist_lookup"' EXIT

if [[ -f "$ALLOWLIST" ]]; then
    python3 -c "
import json, sys
try:
    with open('$ALLOWLIST') as f:
        data = json.load(f)
    for item in data.get('allowed', []):
        print(f\"{item['file']}:{item['line']}:{item['symbol']}\")
except Exception as e:
    sys.stderr.write(f'WARNING: Failed to parse allowlist: {e}\n')
" > "$allowlist_lookup" 2>/dev/null || true
fi

# ─── Scan files for banned symbols ──────────────────────────────────────
violations=0
files_scanned=0

check_category() {
    local category_name="$1"
    local symbols_str="$2"
    local full_path="$3"
    local rel_path="$4"

    for symbol in $symbols_str; do
        while IFS=: read -r line_num _; do
            # Skip if in allowlist
            if grep -q -F -x "$rel_path:$line_num:$symbol" "$allowlist_lookup" 2>/dev/null; then
                continue
            fi
            echo "VIOLATION: $rel_path:$line_num - $symbol ($category_name)"
            violations=$((violations + 1))
        done < <(grep -n -F "$symbol" "$full_path" 2>/dev/null || true)
    done
}

for rel_path in "${files[@]}"; do
    full_path="$REPO_ROOT/$rel_path"
    files_scanned=$((files_scanned + 1))

    check_category "$CAT1_NAME" "$CAT1_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT2_NAME" "$CAT2_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT3_NAME" "$CAT3_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT4_NAME" "$CAT4_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT5_NAME" "$CAT5_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT6_NAME" "$CAT6_SYMBOLS" "$full_path" "$rel_path"
    check_category "$CAT7_NAME" "$CAT7_SYMBOLS" "$full_path" "$rel_path"
done

if [[ $files_scanned -eq 0 ]]; then
    echo "ERROR: No Developer Mode files scanned"
    exit 1
fi

if [[ $violations -gt 0 ]]; then
    echo "Found $violations violation(s)"
    exit 1
fi

echo "No banned symbols found in $files_scanned Developer Mode file(s)"
exit 0
