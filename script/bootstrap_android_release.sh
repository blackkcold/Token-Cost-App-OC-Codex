#!/usr/bin/env bash
# =============================================================================
# bootstrap_android_release.sh — Android Release 签名材料本地缓存播种脚本
#
# 设计目标（签名安全方案 v2）：
#   1Password 只做「首次播种」，之后 keystore + 密码 + alias 全部缓存到本机
#   ~/.config/token-cost/android-release/（目录 0700 / 文件 0600），构建时
#   完全离线、零 1Password、零钥匙串、零授权弹窗。
#
# 安全边界 = 目录权限 + JKS 本身密码加密。机器被攻破时 keystore 与密码
# 都可能泄露，这是「不用钥匙串」的固有代价。
#
# 缓存目录（唯一本机存储）：
#   ~/.config/token-cost/android-release/
#   ├── balance-monitor-release.jks   # 0600，密码加密的 keystore
#   ├── secrets.properties            # 0600，storePassword/keyPassword/keyAlias
#   └── cache.meta                    # 0600，keystore 指纹 + 缓存版本号
#
# 1Password 播种源（唯一源，仅首次访问）：
#   op://Personal/Balance Monitor Release Keystore/...        （LOGIN，密码/alias）
#   op://Personal/Balance Monitor Release Keystore JKS Current/balance-monitor-release.jks
#                                                             （DOCUMENT，当前有效 jks）
#
# 用法：
#   bash script/bootstrap_android_release.sh [bootstrap|refresh|check|help]
#
# 模式：
#   bootstrap  首次播种：从 1Password 拉取并写入 0600 缓存（默认）
#   refresh    强制重拉：keystore 轮换后更新本地缓存
#   check      校验：对比本地缓存指纹与 1Password 元数据，不写任何文件
#   help       显示本说明
#
# 环境变量：
#   OP_ACCOUNT  1Password 账户（默认 my.1password.com）
#   OP_VAULT    1Password Vault 名（默认 Personal）
#   CACHE_DIR   覆盖缓存目录（默认 ~/.config/token-cost/android-release）
# =============================================================================
set -euo pipefail

MODE="${1:-bootstrap}"

# --- 路径 ---
CACHE_DIR="${CACHE_DIR:-$HOME/.config/token-cost/android-release}"
JKS_FILE="$CACHE_DIR/balance-monitor-release.jks"
SECRETS_FILE="$CACHE_DIR/secrets.properties"
META_FILE="$CACHE_DIR/cache.meta"

# --- 1Password 引用（播种源）---
OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
OP_VAULT="${OP_VAULT:-Personal}"
OP_ITEM="Balance Monitor Release Keystore"
OP_DOC_ITEM="Balance Monitor Release Keystore JKS Current"
OP_DOC_FILE="balance-monitor-release.jks"

# --- 帮助 ---
if [[ "$MODE" == "help" || "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

case "$MODE" in
  bootstrap|refresh|check) ;;
  *)
    echo "usage: $0 [bootstrap|refresh|check|help]" >&2
    exit 2
    ;;
esac

# --- 工具检测 ---
if ! command -v op >/dev/null 2>&1; then
  echo "ERROR: 1Password CLI (op) 不在 PATH 中。" >&2
  echo "  请安装 1Password CLI: https://developer.1password.com/docs/cli/get-started/" >&2
  exit 1
fi

# --- 1Password 登录检查（仅 bootstrap/refresh 需要；check 用本地指纹即可）---
require_op_login() {
  if ! op account list >/dev/null 2>&1; then
    echo "ERROR: 1Password CLI 未登录。请先执行: op signin" >&2
    exit 1
  fi
}

# --- 计算 keystore 指纹（SHA-256）---
jks_sha256() {
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

# --- 写 0600 文件（原子：先写临时文件再 mv，避免半写状态）---
write_0600() {
  local target="$1"
  local tmp="$target.tmp.$$"
  cat > "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$target"
  chmod 0600 "$target"
}

# --- 确保缓存目录存在且权限正确 ---
ensure_cache_dir() {
  mkdir -p "$CACHE_DIR"
  chmod 0700 "$CACHE_DIR"
}

# --- 从 1Password 播种（bootstrap/refresh 共用）---
seed_from_1password() {
  require_op_login
  ensure_cache_dir

  echo "==> 从 1Password 播种签名材料到 $CACHE_DIR"

  # 1. keystore 附件（用 --out-file 精确落盘，避免 stdout 追加换行污染二进制）
  op read --out-file "$JKS_FILE.tmp.$$" "op://$OP_VAULT/$OP_DOC_ITEM/$OP_DOC_FILE"
  chmod 0600 "$JKS_FILE.tmp.$$"
  mv "$JKS_FILE.tmp.$$" "$JKS_FILE"
  chmod 0600 "$JKS_FILE"

  # 2. 密码 + alias
  local store_password key_password key_alias
  store_password="$(op read "op://$OP_VAULT/$OP_ITEM/password")"
  key_password="$(op read "op://$OP_VAULT/$OP_ITEM/keyPassword")"
  key_alias="$(op read "op://$OP_VAULT/$OP_ITEM/keyAlias")"

  if [[ -z "$store_password" || -z "$key_password" || -z "$key_alias" ]]; then
    echo "ERROR: 1Password 播种源缺少 password/keyPassword/keyAlias 字段。" >&2
    rm -f "$JKS_FILE"
    exit 1
  fi

  write_0600 "$SECRETS_FILE" <<EOF
storePassword=$store_password
keyPassword=$key_password
keyAlias=$key_alias
EOF

  # 3. 指纹 + 缓存版本号
  local sha
  sha="$(jks_sha256 "$JKS_FILE")"
  if [[ -z "$sha" ]]; then
    echo "ERROR: 无法计算 keystore 指纹。" >&2
    exit 1
  fi
  write_0600 "$META_FILE" <<EOF
keystoreSHA256=$sha
cacheVersion=1
EOF

  echo "==> 播种完成："
  echo "    keystore: $JKS_FILE ($(stat -f '%Sp' "$JKS_FILE"))"
  echo "    secrets:  $SECRETS_FILE ($(stat -f '%Sp' "$SECRETS_FILE"))"
  echo "    meta:     $META_FILE ($(stat -f '%Sp' "$META_FILE"))"
  echo "    keystoreSHA256: $sha"
}

# --- 校验本地缓存是否有效（存在 + 权限 + 指纹）---
cache_valid() {
  [[ -f "$JKS_FILE" && -f "$SECRETS_FILE" && -f "$META_FILE" ]] || return 1
  # 权限检查：目录 0700，文件 0600
  local dir_perm file_perm
  dir_perm="$(stat -f '%Lp' "$CACHE_DIR" 2>/dev/null || echo 0)"
  file_perm="$(stat -f '%Lp' "$JKS_FILE" 2>/dev/null || echo 0)"
  [[ "$dir_perm" == "700" && "$file_perm" == "600" ]] || return 1
  # 指纹自洽：meta 里的指纹与当前 jks 一致
  local meta_sha current_sha
  meta_sha="$(grep '^keystoreSHA256=' "$META_FILE" 2>/dev/null | cut -d= -f2)"
  current_sha="$(jks_sha256 "$JKS_FILE")"
  [[ -n "$meta_sha" && "$meta_sha" == "$current_sha" ]] || return 1
  return 0
}

# --- check 模式：对比本地指纹与 1Password 元数据 ---
check_mode() {
  echo "==> 校验本地缓存指纹与 1Password 元数据"
  if ! cache_valid; then
    echo "    本地缓存无效或缺失，需要 bootstrap/refresh。" >&2
    exit 1
  fi

  local local_sha
  local_sha="$(jks_sha256 "$JKS_FILE")"
  echo "    本地 keystoreSHA256: $local_sha"

  # 尝试从 1Password 读取元数据指纹（只读，不写文件）
  local op_sha=""
  if op account list >/dev/null 2>&1; then
    op_sha="$(op read "op://$OP_VAULT/$OP_ITEM/keystoreSHA256" 2>/dev/null || true)"
  fi

  if [[ -n "$op_sha" ]]; then
    echo "    1Password keystoreSHA256: $op_sha"
    if [[ "$local_sha" == "$op_sha" ]]; then
      echo "    ✓ 指纹一致，缓存有效。"
      exit 0
    else
      echo "    ✗ 指纹不一致！keystore 可能已轮换，请执行 refresh。" >&2
      exit 1
    fi
  else
    echo "    1Password 未登录或无法读取元数据，跳过远端比对。"
    echo "    本地缓存自洽（指纹匹配），视为有效。"
    exit 0
  fi
}

# --- 主流程 ---
case "$MODE" in
  bootstrap)
    if cache_valid; then
      echo "==> 本地缓存已存在且有效，无需播种。"
      echo "    如需强制重拉请执行: $0 refresh"
      exit 0
    fi
    seed_from_1password
    ;;
  refresh)
    seed_from_1password
    ;;
  check)
    check_mode
    ;;
esac
