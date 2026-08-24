#!/usr/bin/env bash
# =============================================================================
# build_android_release.sh — 安卓端（Flutter）构建与打包脚本
#
# 作用：
#   1. 从 pubspec.yaml 解析 Android 独立版本号（可用 ANDROID_VERSION 环境变量覆盖）。
#   2. 构建 release APK（按 ABI 拆分 + universal）+ AAB（App Bundle）。
#   3. 按「版本号-时间戳-PID」命名归档到 App-Builds/<版本>/android/。
#
# 与 macOS 端 build_and_run_codex.sh 保持一致的版本化目录约定：
#   App-Builds/v<版本>-<YYYYMMDD>-<HHMMSS>-<PID>/android/
#
# 用法：
#   bash script/build_android_release.sh [build|release|help]
#
# 环境变量：
#   ANDROID_VERSION   指定 A.BCD.E+code，默认从 pubspec.yaml 读取
#   RELEASE_TS        发布批次时间戳（YYYYMMDD-HHMM），默认取当前 UTC 分钟
#   APP_BUILDS_DIR    覆盖产物根目录（默认仓库同级 ../App-Builds，CI 可覆盖）
#   JAVA_HOME         指向 JDK 17（Android 构建必需）
#   RELAY_BASE_URL    Production Relay HTTPS 地址（必需，不写入仓库）
#
# 模式：
#   build    仅本地构建并归档到 App-Builds/v...-<stamp>-<pid>/android/（默认）
#   release  同 build，供 CI 或正式发布使用（可搭配 ANDROID_VERSION）
#   help     显示本说明
#
# 打包策略（重要）：
#   本脚本不打包 QA 或 Debug 版。归档到 App-Builds/ 的产物均为带签名正式版
#   （release 模式），供正式环境手动测试。
# =============================================================================
set -euo pipefail

MODE="${1:-build}"

# --- 路径 ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
# Workspace-level artifact root. Defaults to the sibling App-Builds directory
# (exact casing) next to this repo; CI can override via APP_BUILDS_DIR.
APP_BUILDS_DIR="${APP_BUILDS_DIR:-$ROOT_DIR/../App-Builds}"
RELEASE_BASE_DIR="$APP_BUILDS_DIR"
PUBSPEC_FILE="$ANDROID_DIR/pubspec.yaml"

# --- 工具检测（仅 build/release 需要；help 直接返回）---
if [[ "$MODE" == "help" || "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# --- 模式校验（在依赖检查前）---
case "$MODE" in
  build|release) ;;
  help|--help|-h) ;;
  *)
    echo "usage: $0 [build|release|help]" >&2
    exit 2
    ;;
esac

# --- 版本号解析 ---
resolve_version() {
  local raw=""
  if [[ -n "${ANDROID_VERSION:-}" ]]; then
    raw="$ANDROID_VERSION"
  elif [[ -f "$PUBSPEC_FILE" ]]; then
    raw="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC_FILE" | head -1)"
  fi
  if [[ -z "$raw" ]]; then
    echo "ERROR: 无法解析 Android 版本号，请设置 ANDROID_VERSION 或检查 pubspec.yaml。" >&2
    exit 1
  fi

  if [[ ! "$raw" =~ ^([1-9][0-9]{0,3})\.([0-9]{3})\.([0-9])\+([1-9][0-9]{0,9})$ ]]; then
    echo "ERROR: Android 版本必须匹配 A.BCD.E+code（A≥1，BCD=001–999，E=0–9）。收到: $raw" >&2
    exit 1
  fi

  local major="${BASH_REMATCH[1]}"
  local bcd="${BASH_REMATCH[2]}"
  local edition="${BASH_REMATCH[3]}"
  local code="${BASH_REMATCH[4]}"
  local major_number=$((10#$major))
  local bcd_number=$((10#$bcd))
  local edition_number=$((10#$edition))
  local code_number=$((10#$code))

  if (( bcd_number < 1 || bcd_number > 999 )); then
    echo "ERROR: Android 版本 BCD 必须在 001–999。收到: $bcd" >&2
    exit 1
  fi
  if (( code_number > 2100000000 )); then
    echo "ERROR: Android versionCode 不得超过 2,100,000,000。收到: $code" >&2
    exit 1
  fi

  local expected_code=$((major_number * 1000000 + bcd_number * 1000 + edition_number))
  if (( code_number != expected_code )); then
    echo "ERROR: Android versionCode 必须等于 A×1,000,000 + BCD×1,000 + E；预期 $expected_code，收到 $code。" >&2
    exit 1
  fi

  printf '%s|%s\n' "${major}.${bcd}.${edition}" "$code_number"
}

VERSION_DATA="$(resolve_version)"
VERSION_NUMBER="${VERSION_DATA%%|*}"
VERSION_CODE="${VERSION_DATA##*|}"
RELEASE_TAG="v${VERSION_NUMBER}"
RELEASE_TS="${RELEASE_TS:-$(date -u +%Y%m%d-%H%M)}"
if [[ ! "$RELEASE_TS" =~ ^[0-9]{8}-[0-9]{4}$ ]]; then
  echo "ERROR: RELEASE_TS 必须匹配 YYYYMMDD-HHMM" >&2
  exit 1
fi
RELEASE_FULL_VERSION="${RELEASE_TAG}-${RELEASE_TS}"

# --- 工具与构建参数检测（输入校验通过后）---
if [[ -z "${JAVA_HOME:-}" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "ERROR: JAVA_HOME 未设置，且系统未发现 JDK 17。" >&2
  echo "  请安装 JDK 17，或用: export JAVA_HOME=\"/path/to/jdk-17.x/Contents/Home\"" >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter 不在 PATH 中。请将 Flutter SDK 的 bin 目录加入 PATH。" >&2
  exit 1
fi
if [[ ! "${RELAY_BASE_URL:-}" =~ ^https://[^[:space:]?#]+(/[^[:space:]?#]*)?$ ]]; then
  echo "ERROR: RELAY_BASE_URL 必须是无 query/fragment 的 HTTPS URL。" >&2
  exit 1
fi

# --- 时间戳 + PID（复用根脚本 build_and_run_codex.sh 的格式）---
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stripped="${BUILD_TIMESTAMP//[-:TZ]/}"
RELEASE_STAMP="${stripped:0:8}-${stripped:8:6}-$$"
LOCAL_RELEASE_DIR="$RELEASE_BASE_DIR/${RELEASE_TAG}-${RELEASE_STAMP}/android"
OFFICIAL_RELEASE_DIR="$RELEASE_BASE_DIR/$RELEASE_FULL_VERSION/android"
LATEST_RELEASE_DIR="$RELEASE_BASE_DIR/latest/android"
RELEASE_DIR="$LOCAL_RELEASE_DIR"

case "$MODE" in
  release)
    RELEASE_DIR="$OFFICIAL_RELEASE_DIR"
    ;;
  build)
    RELEASE_DIR="$LOCAL_RELEASE_DIR"
    ;;
esac

# --- 归档文件名 ---
APK_BASE="balance-monitor-${RELEASE_FULL_VERSION}-android"
SYMBOL_DIR="$ANDROID_DIR/build/symbols/$RELEASE_TAG"

ensure_flutter_deps() {
  echo "==> flutter pub get"
  (cd "$ANDROID_DIR" && flutter pub get) >/dev/null 2>&1 || {
    echo "ERROR: flutter pub get 失败" >&2
    exit 1
  }
}

build_apk() {
  echo "==> flutter build apk --release (endpoint injected, obfuscated)"
  mkdir -p "$SYMBOL_DIR"
  (cd "$ANDROID_DIR" && flutter build apk --release \
    --build-name="$VERSION_NUMBER" \
    --build-number="$VERSION_CODE" \
    --dart-define=RELAY_BASE_URL="$RELAY_BASE_URL" \
    --obfuscate \
    --split-debug-info="$SYMBOL_DIR") 2>&1 | tail -3
}

build_aab() {
  echo "==> flutter build appbundle --release (endpoint injected, obfuscated)"
  mkdir -p "$SYMBOL_DIR"
  (cd "$ANDROID_DIR" && flutter build appbundle --release \
    --build-name="$VERSION_NUMBER" \
    --build-number="$VERSION_CODE" \
    --dart-define=RELAY_BASE_URL="$RELAY_BASE_URL" \
    --obfuscate \
    --split-debug-info="$SYMBOL_DIR") 2>&1 | tail -3
}

# Move a pre-existing platform-scoped destination into App-Builds/.archive with
# a collision-safe name before it is recreated, instead of deleting it.
archive_existing() {
  local target="$1"
  [[ -e "$target" ]] || return 0
  local archive_root="$RELEASE_BASE_DIR/.archive"
  local base
  base="$(basename "$target")"
  local dest="$archive_root/$base"
  local n=1
  while [[ -e "$dest" ]]; do
    dest="$archive_root/${base}.${n}"
    n=$((n + 1))
  done
  mkdir -p "$archive_root"
  mv "$target" "$dest"
}

stage_artifacts() {
  echo "==> 归档产物到 $RELEASE_DIR"
  archive_existing "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"

  local out="$ANDROID_DIR/build/app/outputs"
  local flutter_apk_dir="$out/flutter-apk"
  local aab_dir="$out/bundle/release"

  # 按 ABI 拆分的 APK + universal
  local abi
  for abi in arm64-v8a armeabi-v7a x86_64; do
    if [[ -f "$flutter_apk_dir/app-${abi}-release.apk" ]]; then
      cp "$flutter_apk_dir/app-${abi}-release.apk" \
        "$RELEASE_DIR/${APK_BASE}-${abi}-release.apk"
    fi
  done
  # universal（flutter build apk 会同时产出 app-release.apk）
  if [[ -f "$flutter_apk_dir/app-release.apk" ]]; then
    cp "$flutter_apk_dir/app-release.apk" \
      "$RELEASE_DIR/${APK_BASE}-universal-release.apk"
  fi
  # AAB
  if [[ -f "$aab_dir/app-release.aab" ]]; then
    cp "$aab_dir/app-release.aab" \
      "$RELEASE_DIR/${APK_BASE}-release.aab"
  fi

  # 同步到 App-Builds/latest/android（平台作用域，避免与 macOS 产物互相覆盖）
  archive_existing "$LATEST_RELEASE_DIR"
  mkdir -p "$LATEST_RELEASE_DIR"
  cp "$RELEASE_DIR"/* "$LATEST_RELEASE_DIR/"

  echo "==> 归档完成，产物："
  ls -lh "$RELEASE_DIR"
  echo "==> 调试符号保留在本地受忽略目录: android/build/symbols/$RELEASE_TAG"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "release_dir=$RELEASE_DIR" >> "$GITHUB_OUTPUT"
  fi
}

case "$MODE" in
  build|release)
    ensure_flutter_deps
    build_apk
    build_aab
    stage_artifacts
    ;;
  *)
    echo "usage: $0 [build|release|help]" >&2
    exit 2
    ;;
esac
