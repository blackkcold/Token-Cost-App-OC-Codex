#!/usr/bin/env bash
# =============================================================================
# build_android_release.sh — 安卓端（Flutter）构建与打包脚本
#
# 作用：
#   1. 从 pubspec.yaml 解析版本号（可用 RELEASE_VERSION 环境变量覆盖）。
#   2. 构建 release APK（按 ABI 拆分 + universal）+ AAB（App Bundle）。
#   3. 按「版本号-时间戳-PID」命名归档到 android/release/。
#
# 与 macOS 端 build_and_run_codex.sh 保持一致的版本化目录约定：
#   android/release/v<版本>-<YYYYMMDD>-<HHMMSS>-<PID>/
#
# 用法：
#   bash script/build_android_release.sh [build|release|help]
#
# 环境变量：
#   RELEASE_VERSION   指定版本号（如 v1.0.0 或 1.0.0），默认从 pubspec.yaml 读取
#   JAVA_HOME         指向 JDK 17（Android 构建必需）
#   RELAY_BASE_URL    Production Relay HTTPS 地址（必需，不写入仓库）
#
# 模式：
#   build    仅本地构建并归档到 android/release/v...-<stamp>-<pid>/（默认）
#   release  同 build，供 CI 或正式发布使用（可搭配 RELEASE_VERSION）
#   help     显示本说明
# =============================================================================
set -euo pipefail

MODE="${1:-build}"

# --- 路径 ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
RELEASE_BASE_DIR="$ANDROID_DIR/release"
PUBSPEC_FILE="$ANDROID_DIR/pubspec.yaml"

# --- 工具检测（仅 build/release 需要；help 直接返回）---
if [[ "$MODE" == "help" || "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
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

# --- 版本号解析 ---
resolve_version() {
  if [[ -n "${RELEASE_VERSION:-}" ]]; then
    case "$RELEASE_VERSION" in
      v*) printf '%s\n' "$RELEASE_VERSION" ;;
      *)  printf 'v%s\n' "$RELEASE_VERSION" ;;
    esac
    return
  fi

  # 从 pubspec.yaml 读取 version: 字段（格式 1.0.0+1）
  local raw=""
  if [[ -f "$PUBSPEC_FILE" ]]; then
    raw="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC_FILE" | head -1)"
  fi
  if [[ -z "$raw" ]]; then
    echo "ERROR: 无法从 pubspec.yaml 解析版本号，请设置 RELEASE_VERSION。" >&2
    exit 1
  fi
  # 去掉 +buildNumber 后缀，保留语义版本 1.0.0
  printf 'v%s\n' "${raw%%+*}"
}

RELEASE_TAG="$(resolve_version)"
VERSION_NUMBER="${RELEASE_TAG#v}"

# --- 时间戳 + PID（复用根脚本 build_and_run_codex.sh 的格式）---
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stripped="${BUILD_TIMESTAMP//[-:TZ]/}"
RELEASE_STAMP="${stripped:0:8}-${stripped:8:6}-$$"
RELEASE_DIR="$RELEASE_BASE_DIR/${RELEASE_TAG}-${RELEASE_STAMP}"

# --- 归档文件名 ---
APK_BASE="balance-monitor-${RELEASE_TAG}-android"
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
    --dart-define=RELAY_BASE_URL="$RELAY_BASE_URL" \
    --obfuscate \
    --split-debug-info="$SYMBOL_DIR") 2>&1 | tail -3
}

build_aab() {
  echo "==> flutter build appbundle --release (endpoint injected, obfuscated)"
  mkdir -p "$SYMBOL_DIR"
  (cd "$ANDROID_DIR" && flutter build appbundle --release \
    --dart-define=RELAY_BASE_URL="$RELAY_BASE_URL" \
    --obfuscate \
    --split-debug-info="$SYMBOL_DIR") 2>&1 | tail -3
}

stage_artifacts() {
  echo "==> 归档产物到 $RELEASE_DIR"
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

  echo "==> 归档完成，产物："
  ls -lh "$RELEASE_DIR"
  echo "==> 调试符号保留在本地受忽略目录: android/build/symbols/$RELEASE_TAG"
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
