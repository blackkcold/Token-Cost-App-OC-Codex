#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_BASE_DIR="$ROOT_DIR/release"
APP_DISPLAY_NAME="Token Cost App - OC Codex"
APP_EXECUTABLE_NAME="CodexTokenCostApp"
HELPER_EXECUTABLE_NAME="CodexTokenCostHelper"
BUNDLE_ID="com.yanghaoran.CodexTokenCost"
MIN_SYSTEM_VERSION="14.0"
SWIFT_SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"

resolve_release_tag() {
  if [[ -n "${RELEASE_VERSION:-}" ]]; then
    case "$RELEASE_VERSION" in
      v*) printf '%s\n' "$RELEASE_VERSION" ;;
      *) printf 'v%s\n' "$RELEASE_VERSION" ;;
    esac
    return
  fi

  local tag=""
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tag="$(git -C "$ROOT_DIR" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)"
  fi

  if [[ -n "$tag" ]]; then
    printf '%s\n' "$tag"
    return
  fi

  if [[ "$MODE" != "release" ]]; then
    # Prefer the nearest already-released git tag (e.g. v0.9.8) over the
    # CHANGELOG "Unreleased" entry, which tracks the in-development target
    # version and would otherwise inflate the local build version. Also
    # preferred over scanning local release directories, which may lag
    # behind when releases are built via CI and their artifacts were never
    # synced locally.
    tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return
    fi

    # Fall back to CHANGELOG "Unreleased" only when no git tag exists at all
    # (e.g. a brand-new repo before the first release). Conforms to Keep a
    # Changelog convention.
    if [[ -f "$ROOT_DIR/CHANGELOG.md" ]]; then
      local changelog_tag=""
      changelog_tag="$(sed -n 's/^## \[\(v[0-9.]*\)\] - Unreleased.*/\1/p' "$ROOT_DIR/CHANGELOG.md" | head -1)"
      if [[ -n "$changelog_tag" ]]; then
        printf '%s\n' "$changelog_tag"
        return
      fi
    fi

    local release_tag=""
    release_tag="$(resolve_latest_release_tag)"
    if [[ -n "$release_tag" ]]; then
      printf '%s\n' "$release_tag"
      return
    fi

    printf 'v0.0.0\n'
    return
  fi

  echo "release mode requires RELEASE_VERSION or an exact git tag" >&2
  exit 3
}

semver_greater() {
  local left right
  local left_major left_minor left_patch
  local right_major right_minor right_patch

  left="${1#v}"
  right="${2#v}"
  IFS=. read -r left_major left_minor left_patch <<<"$left"
  IFS=. read -r right_major right_minor right_patch <<<"$right"

  (( left_major > right_major )) && return 0
  (( left_major < right_major )) && return 1
  (( left_minor > right_minor )) && return 0
  (( left_minor < right_minor )) && return 1
  (( left_patch > right_patch )) && return 0
  return 1
}

resolve_latest_release_tag() {
  local latest=""
  local candidate=""
  local dir

  shopt -s nullglob
  for dir in "$RELEASE_BASE_DIR"/v[0-9]*.[0-9]*.[0-9]*; do
    [[ -d "$dir" ]] || continue
    candidate="$(basename "$dir")"
    if [[ ! "$candidate" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      continue
    fi
    if [[ -z "$latest" ]] || semver_greater "$candidate" "$latest"; then
      latest="$candidate"
    fi
  done
  shopt -u nullglob

  printf '%s\n' "$latest"
}

RELEASE_TAG="$(resolve_release_tag)"
RELEASE_VERSION_NUMBER="${RELEASE_TAG#v}"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stripped="${BUILD_TIMESTAMP//[-:TZ]/}"
RELEASE_STAMP="${stripped:0:8}-${stripped:8:6}-$$"
LOCAL_RELEASE_DIR="$RELEASE_BASE_DIR/${RELEASE_TAG}-${RELEASE_STAMP}"
OFFICIAL_RELEASE_DIR="$RELEASE_BASE_DIR/$RELEASE_TAG"
BUILD_CONFIGURATION="debug"
RELEASE_DIR="$LOCAL_RELEASE_DIR"
APP_ARCH="$(uname -m)"
APP_ZIP_NAME="Token-Cost-App-OC-Codex-${RELEASE_TAG}-macOS-${APP_ARCH}.zip"
APP_DMG_NAME="Token-Cost-App-OC-Codex-${RELEASE_TAG}-macOS-${APP_ARCH}.dmg"
UPDATE_MANIFEST_NAME="Token-Cost-App-OC-Codex-${RELEASE_TAG}-macOS-${APP_ARCH}.update-manifest.json"
APP_VOLUME_NAME="Token Cost App - OC Codex"
UPDATE_MANIFEST_PUBLIC_KEY_B64="${UPDATE_MANIFEST_PUBLIC_KEY_B64:-}"
RELAY_BASE_URL="${RELAY_BASE_URL:-}"

case "$MODE" in
  release)
    BUILD_CONFIGURATION="release"
    RELEASE_DIR="$OFFICIAL_RELEASE_DIR"
    ;;
  run|build|debug|logs|telemetry|verify|--debug|--logs|--telemetry|--verify)
    BUILD_CONFIGURATION="debug"
    RELEASE_DIR="$LOCAL_RELEASE_DIR"
    ;;
  *)
    echo "usage: $0 [run|build|release|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

if [[ "$MODE" == "release" ]]; then
  if [[ ! "$RELAY_BASE_URL" =~ ^https://[^[:space:]?#]+(/[^[:space:]?#]*)?$ ]]; then
    echo "release mode requires a valid HTTPS RELAY_BASE_URL without query or fragment" >&2
    exit 4
  fi
elif [[ -n "$RELAY_BASE_URL" ]] && [[ ! "$RELAY_BASE_URL" =~ ^https?://[^[:space:]?#]+(/[^[:space:]?#]*)?$ ]]; then
  echo "RELAY_BASE_URL must be an HTTP(S) URL without query or fragment" >&2
  exit 4
fi

RELAY_PLIST_ENTRY=""
if [[ -n "$RELAY_BASE_URL" ]]; then
  RELAY_PLIST_ENTRY="  <key>RelayBaseURL</key>
  <string>$RELAY_BASE_URL</string>"
fi

APP_BUNDLE="$RELEASE_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
HELPER_BINARY="$APP_HELPERS/$HELPER_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCES_SOURCE="$ROOT_DIR/Resources"

kill_running() {
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
  pkill -x "$HELPER_EXECUTABLE_NAME" >/dev/null 2>&1 || true
  sleep 1
}

stage_bundle() {
  local swift_build_flags=(
    --disable-sandbox
    --sdk "$SWIFT_SDK_ROOT"
    -c "$BUILD_CONFIGURATION"
  )
  local build_binary_dir

  rm -rf "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"

  HOME=/private/tmp swift build "${swift_build_flags[@]}"
  build_binary_dir="$(HOME=/private/tmp swift build "${swift_build_flags[@]}" --show-bin-path)"

  mkdir -p "$APP_MACOS"
  mkdir -p "$APP_HELPERS"

  cp "$build_binary_dir/$APP_EXECUTABLE_NAME" "$APP_BINARY"
  cp "$build_binary_dir/$HELPER_EXECUTABLE_NAME" "$HELPER_BINARY"
  chmod +x "$APP_BINARY" "$HELPER_BINARY"
  mkdir -p "$APP_RESOURCES"
  if [[ -d "$RESOURCES_SOURCE" ]]; then
    ditto "$RESOURCES_SOURCE" "$APP_RESOURCES"
  fi

  # Validate that all runtime resources expected by ProviderLogoMark and the
  # app are present inside Contents/Resources before codesigning.  The shell
  # script copies Resources/ into Contents/Resources, so ProviderLogoMark
  # loads SVGs via Bundle.main.  Bundle.module is deliberately unused — the
  # SPM resource bundle at the app wrapper root would break code signing.
  local missing=0
  for svg in opencode_go opencode_zen codex deepseek ollama; do
    if [[ ! -f "$APP_RESOURCES/ProviderLogos/${svg}.svg" ]]; then
      echo "ERROR: missing $APP_RESOURCES/ProviderLogos/${svg}.svg" >&2
      missing=1
    fi
  done
  for lproj in en.lproj zh-Hans.lproj; do
    if [[ ! -d "$APP_RESOURCES/$lproj" ]]; then
      echo "ERROR: missing $APP_RESOURCES/$lproj" >&2
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    exit 1
  fi

  printf 'APPL????' >"$APP_CONTENTS/PkgInfo"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$RELEASE_VERSION_NUMBER</string>
  <key>CFBundleVersion</key>
  <string>$RELEASE_VERSION_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>UpdateManifestPublicKey</key>
  <string>$UPDATE_MANIFEST_PUBLIC_KEY_B64</string>
$RELAY_PLIST_ENTRY
</dict>
</plist>
PLIST

  codesign --force --deep --sign - "$APP_BUNDLE"
}

package_release_zip() {
  local zip_path="$RELEASE_DIR/$APP_ZIP_NAME"

  rm -f "$zip_path"
  (
    cd "$RELEASE_DIR"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DISPLAY_NAME.app" "$APP_ZIP_NAME"
  )
}

write_update_manifest() {
  local zip_path="$RELEASE_DIR/$APP_ZIP_NAME"
  local manifest_path="$RELEASE_DIR/$UPDATE_MANIFEST_NAME"
  local asset_size sha256 signature signing_payload

  if [[ -z "${UPDATE_MANIFEST_PRIVATE_KEY_PEM:-}" ]] || [[ -z "$UPDATE_MANIFEST_PUBLIC_KEY_B64" ]]; then
    echo "warning: UPDATE_MANIFEST_PRIVATE_KEY_PEM or UPDATE_MANIFEST_PUBLIC_KEY_B64 not set; skipping signed update manifest" >&2
    return 0
  fi

  asset_size="$(stat -f '%z' "$zip_path")"
  sha256="$(shasum -a 256 "$zip_path" | cut -d ' ' -f 1)"
  signing_payload="$(mktemp)"
  trap 'rm -f "$signing_payload"' RETURN
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$RELEASE_TAG" "$BUNDLE_ID" "$APP_ARCH" "$APP_ZIP_NAME" "$asset_size" "$sha256" \
    >"$signing_payload"
  signature="$(
    openssl pkeyutl -sign -rawin \
      -inkey <(printf '%s' "$UPDATE_MANIFEST_PRIVATE_KEY_PEM") \
      -in "$signing_payload" \
      | openssl base64 -A
  )"
  rm -f "$signing_payload"
  trap - RETURN

  python3 - "$manifest_path" "$RELEASE_TAG" "$BUNDLE_ID" "$APP_ARCH" "$APP_ZIP_NAME" "$asset_size" "$sha256" "$signature" <<'PY'
import json
import sys

path, version, bundle_id, architecture, asset_name, asset_size, sha256, signature = sys.argv[1:]
with open(path, "w", encoding="utf-8") as output:
    json.dump({
        "version": version,
        "bundleIdentifier": bundle_id,
        "architecture": architecture,
        "assetName": asset_name,
        "assetSize": int(asset_size),
        "sha256": sha256,
        "signature": signature,
    }, output, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    output.write("\n")
PY
}

package_release_dmg() {
  local dmg_path="$RELEASE_DIR/$APP_DMG_NAME"
  local temp_dir
  temp_dir="$(mktemp -d)"
  ditto "$APP_BUNDLE" "$temp_dir/$APP_DISPLAY_NAME.app"
  ln -s /Applications "$temp_dir/Applications"
  rm -f "$dmg_path"
  hdiutil create -volname "$APP_VOLUME_NAME" \
    -srcfolder "$temp_dir" \
    -ov -format UDZO \
    "$dmg_path"
  rm -rf "$temp_dir"
}

update_latest() {
  rm -rf "$RELEASE_BASE_DIR/latest"
  mkdir -p "$RELEASE_BASE_DIR/latest"
  touch "$RELEASE_BASE_DIR/latest/.gitkeep"
  ditto "$APP_BUNDLE" "$RELEASE_BASE_DIR/latest/$APP_DISPLAY_NAME.app"
  if [[ "$MODE" == "release" ]] && [[ -f "$RELEASE_DIR/$APP_ZIP_NAME" ]]; then
    cp "$RELEASE_DIR/$APP_ZIP_NAME" "$RELEASE_BASE_DIR/latest/$APP_ZIP_NAME"
  fi
  if [[ "$MODE" == "release" ]] && [[ -f "$RELEASE_DIR/$APP_DMG_NAME" ]]; then
    cp "$RELEASE_DIR/$APP_DMG_NAME" "$RELEASE_BASE_DIR/latest/$APP_DMG_NAME"
  fi
}

write_build_info() {
  local info_file="$RELEASE_BASE_DIR/latest/BUILD_INFO.txt"
  cat >"$info_file" <<INFO
# Build Info — Token Cost App — OC Codex
# This file is written only for non-release (development) builds.
# Release builds use the official versioned directory structure instead.

Version:     $RELEASE_TAG
Mode:        $MODE
Arch:        $APP_ARCH
Built:       $BUILD_TIMESTAMP
INFO
}

update_versions_json() {
  local versions_file="$RELEASE_BASE_DIR/versions.json"
  local today
  today="$(date +%Y-%m-%d)"

  if [[ ! -f "$versions_file" ]]; then
    echo '[]' >"$versions_file"
  fi

  python3 -c "
import json
entry = {'version': '${RELEASE_VERSION_NUMBER}', 'date': '${today}', 'file': '${APP_ZIP_NAME}', 'type': 'release'}
with open('${versions_file}', 'r') as f:
    data = json.load(f)
data = [e for e in data if not (e.get('version') == entry['version'] and e.get('type') == entry['type'])]
data.append(entry)
def sort_key(e):
    t = e.get('type', '')
    d = e.get('date', '')
    return (0 if t == 'release' else 1, d)
data.sort(key=sort_key)
with open('${versions_file}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null || true
}

launch_bundle() {
  /usr/bin/open -n "$APP_BUNDLE"
}

kill_running
stage_bundle
update_latest

if [[ "$MODE" != "release" ]]; then
  write_build_info
fi

case "$MODE" in
  run)
    launch_bundle
    ;;
  build)
    ;;
  release)
    package_release_zip
    write_update_manifest
    package_release_dmg
    update_latest
    update_versions_json
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    launch_bundle
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    launch_bundle
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    launch_bundle
    sleep 2
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
esac
