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

  if [[ "$MODE" != "release" ]] && [[ -f "$ROOT_DIR/CHANGELOG.md" ]]; then
    local changelog_tag=""
    changelog_tag="$(sed -n 's/^## \[\(v[0-9.]*\)\] - Unreleased.*/\1/p' "$ROOT_DIR/CHANGELOG.md" | head -1)"
    if [[ -n "$changelog_tag" ]]; then
      printf '%s\n' "$changelog_tag"
      return
    fi
  fi

  if [[ "$MODE" != "release" ]]; then
    local release_tag=""
    release_tag="$(resolve_latest_release_tag)"
    if [[ -n "$release_tag" ]]; then
      printf '%s\n' "$release_tag"
      return
    fi

    tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
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
RELEASE_STAMP="$(date +%Y%m%d-%H%M%S)-$$"
LOCAL_RELEASE_DIR="$RELEASE_BASE_DIR/${RELEASE_TAG}-${RELEASE_STAMP}"
OFFICIAL_RELEASE_DIR="$RELEASE_BASE_DIR/$RELEASE_TAG"
BUILD_CONFIGURATION="debug"
RELEASE_DIR="$LOCAL_RELEASE_DIR"
APP_ARCH="$(uname -m)"
APP_ZIP_NAME="Token-Cost-App-OC-Codex-${RELEASE_TAG}-macOS-${APP_ARCH}.zip"

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

update_latest() {
  rm -rf "$RELEASE_BASE_DIR/latest"
  mkdir -p "$RELEASE_BASE_DIR/latest"
  touch "$RELEASE_BASE_DIR/latest/.gitkeep"
  ditto "$APP_BUNDLE" "$RELEASE_BASE_DIR/latest/$APP_DISPLAY_NAME.app"
  if [[ "$MODE" == "release" ]] && [[ -f "$RELEASE_DIR/$APP_ZIP_NAME" ]]; then
    cp "$RELEASE_DIR/$APP_ZIP_NAME" "$RELEASE_BASE_DIR/latest/$APP_ZIP_NAME"
  fi
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

case "$MODE" in
  run)
    launch_bundle
    ;;
  build)
    ;;
  release)
    package_release_zip
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
