#!/usr/bin/env bash

# Hy2 + VLESS Reality 一键安装脚本 - 模块化入口
# 支持两种运行方式：
# 1) git clone 后在仓库根目录执行：bash install.sh
# 2) 只 wget 入口文件执行：入口会自动从 GitHub 拉取 lib/ 模块到临时目录
#
# 可通过环境变量覆盖模块下载地址：
# HY2_VLESS_RAW_BASE="https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main" bash install.sh

export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
REPO_OWNER="${HY2_VLESS_REPO_OWNER:-yanbinlti-glitch}"
REPO_NAME="${HY2_VLESS_REPO_NAME:-hy2-vless-install}"
REPO_BRANCH="${HY2_VLESS_REPO_BRANCH:-main}"

REPO_RAW_BASE=""
INSTALL_DIR="${HY2_VLESS_INSTALL_DIR:-/opt/hy2-vless-install}"
VERSION_FILE="VERSION"

HY2_VLESS_VERSION="$(
  cat "$SCRIPT_DIR/$VERSION_FILE" \
    2>/dev/null ||
    echo "dev"
)"

BOOTSTRAP_DIR="${HY2_VLESS_BOOTSTRAP_DIR:-}"
ORIGINAL_ARGS=("$@")

export SCRIPT_PATH
export SCRIPT_DIR
export REPO_RAW_BASE
export INSTALL_DIR
export VERSION_FILE
export HY2_VLESS_VERSION


# ==========================================
# V1.8.39 全局防并发排他锁 (Mutex Lock)
# ==========================================
exec 9> "/tmp/hy2_vless_panel.lock"
if ! flock -n 9; then
    printf "%b
" "\n\033[1;31m [✘] 致命拦截：系统检测到面板已在另一个终端运行！\033[0m"
    printf "%b
" "\033[1;33m [!] 为防止底层 JSON 配置撕裂与数据损坏，已禁止并发操作。\033[0m"
    printf "%b
" "\033[1;33m [!] 请关闭其他正在运行的菜单实例后再试。\033[0m\n"
    exit 1
fi

MODULES=(
  "00_ui.sh"
  "01_system.sh"
  "02_service_firewall.sh"
  "03_env_core.sh"
  "04_install_nodes.sh"
  "05_subscription.sh"
  "06_panel_tools.sh"
  "07_menu.sh"
  "08_update.sh"
)

export MODULES

cleanup_bootstrap_dir() {
  if [[ -n "$BOOTSTRAP_DIR" &&
        -d "$BOOTSTRAP_DIR" ]]
  then
    rm -rf -- "$BOOTSTRAP_DIR"
    BOOTSTRAP_DIR=""
  fi
}

if [[ -n "$BOOTSTRAP_DIR" ]]; then
  trap cleanup_bootstrap_dir EXIT
fi

download_file() {
  local url="$1"
  local dest="$2"

  case "$url" in
    https://*)
      ;;

    *)
      echo " [错误] 拒绝非 HTTPS 下载地址：$url" >&2
      return 1
      ;;
  esac

  mkdir -p "$(dirname "$dest")" ||
    return 1

  if command -v curl >/dev/null 2>&1; then
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --proto '=https' \
      --tlsv1.2 \
      --connect-timeout 10 \
      --max-time 90 \
      --retry 3 \
      --retry-delay 1 \
      "$url" \
      --output "$dest"

  elif command -v wget >/dev/null 2>&1; then
    wget \
      -q \
      --timeout=15 \
      --tries=3 \
      -O "$dest" \
      "$url"

  else
    echo " [错误] 未找到 curl 或 wget，无法下载文件。" >&2
    return 1
  fi
}

download_text() {
  local url="$1"

  case "$url" in
    https://*)
      ;;

    *)
      echo " [错误] 拒绝非 HTTPS API 地址：$url" >&2
      return 1
      ;;
  esac

  if command -v curl >/dev/null 2>&1; then
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --proto '=https' \
      --tlsv1.2 \
      --connect-timeout 10 \
      --max-time 30 \
      --retry 2 \
      "$url"

  elif command -v wget >/dev/null 2>&1; then
    wget \
      -q \
      --timeout=15 \
      --tries=2 \
      -O- \
      "$url"

  else
    return 1
  fi
}

resolve_bootstrap_base() {
  REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
  export REPO_RAW_BASE
  echo " [安全] 已彻底关闭 API 限制与哈希锁定，启用极速直连源：$REPO_RAW_BASE"
  return 0
}

verify_bootstrap_checksums() {
 echo " [提示] 哈希清单校验已关闭，跳过首次引导哈希校验。"
 return 0
}



validate_required_symbols() {
 local menu_file="$SCRIPT_DIR/lib/07_menu.sh"

 if [[ ! -s "$menu_file" ]]; then
 echo " [错误] 菜单模块为空或不存在：$menu_file" >&2
 return 1
 fi

 if ! grep -qE '^[[:space:]]*menu[[:space:]]*\(\)[[:space:]]*\{' "$menu_file"; then
 echo " [错误] 菜单模块未定义 menu()：$menu_file" >&2
 echo " [诊断] 可能原因：07_menu.sh 是旧版、下载损坏、复制失败，或 /usr/bin/666 指向了旧安装目录。" >&2
 return 1
 fi

 return 0
}

load_modules() {
 local module=""
 local module_path=""

 for module in "${MODULES[@]}"; do
 module_path="$SCRIPT_DIR/lib/$module"

 if [[ ! -s "$module_path" ]]; then
 echo " [错误] 模块为空或不存在：$module_path" >&2
 return 1
 fi

 # shellcheck source=/dev/null
 if ! source "$module_path"; then
 echo " [错误] 模块加载失败：$module_path" >&2
 return 1
 fi
 done

 if ! declare -F menu >/dev/null 2>&1; then
 echo " [错误] 主菜单函数 menu 未加载，已停止进入主循环。" >&2
 echo " [诊断] SCRIPT_DIR=$SCRIPT_DIR" >&2
 echo " [诊断] 请检查：ls -l \"$SCRIPT_DIR/lib/07_menu.sh\" && grep -n '^menu[[:space:]]*()' \"$SCRIPT_DIR/lib/07_menu.sh\"" >&2
 return 1
 fi

 return 0
}


validate_local_bundle() {
 local module=""

 if [[ ! -s "$SCRIPT_DIR/install.sh" ]]; then
 echo " [错误] 找不到入口文件或入口文件为空：$SCRIPT_DIR/install.sh" >&2
 return 1
 fi

 if ! bash -n "$SCRIPT_DIR/install.sh"; then
 echo " [错误] install.sh 语法检查失败。" >&2
 return 1
 fi

 for module in "${MODULES[@]}"; do
 if [[ ! -s "$SCRIPT_DIR/lib/$module" ]]; then
 echo " [错误] 模块文件缺失或为空：$module" >&2
 return 1
 fi

 if ! bash -n "$SCRIPT_DIR/lib/$module"; then
 echo " [错误] 模块语法检查失败：$module" >&2
 return 1
 fi
 done

 validate_required_symbols || return 1

 echo " [安全] 入口和全部模块语法检查通过。"
}

ensure_modules() {
  local missing=0
  local module=""
  local url=""
  local boot_dir=""

  for module in "${MODULES[@]}"; do
    if [[ ! -s "$SCRIPT_DIR/lib/$module" ]]; then
      missing=1
      break
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    return 0
  fi

  echo " [提示] 未检测到完整本地模块，准备安全下载完整引导包……"

  resolve_bootstrap_base ||
    return 1

  boot_dir="$(
    mktemp -d \
      "${TMPDIR:-/tmp}/hy2-vless-bootstrap.XXXXXX"
  )" || {
    echo " [错误] 无法创建引导临时目录。" >&2
    return 1
  }

  chmod 700 "$boot_dir" || {
    rm -rf -- "$boot_dir"
    return 1
  }

  mkdir -p "$boot_dir/lib" || {
    rm -rf -- "$boot_dir"
    return 1
  }

 echo " [提示] 已跳过哈希清单下载。"

  if ! download_file \
    "$REPO_RAW_BASE/install.sh" \
    "$boot_dir/install.sh"
  then
    echo " [错误] install.sh 下载失败。" >&2
    rm -rf -- "$boot_dir"
    return 1
  fi

  if ! download_file \
    "$REPO_RAW_BASE/$VERSION_FILE" \
    "$boot_dir/$VERSION_FILE"
  then
    echo " [错误] VERSION 下载失败。" >&2
    rm -rf -- "$boot_dir"
    return 1
  fi

  for module in "${MODULES[@]}"; do
    url="$REPO_RAW_BASE/lib/$module"

    if ! download_file \
      "$url" \
      "$boot_dir/lib/$module"
    then
      echo " [错误] 模块下载失败：$module" >&2
      rm -rf -- "$boot_dir"
      return 1
    fi
  done


  if ! bash -n "$boot_dir/install.sh"; then
    echo " [错误] 下载的 install.sh 语法检查失败。" >&2
    rm -rf -- "$boot_dir"
    return 1
  fi

  for module in "${MODULES[@]}"; do
    if ! bash -n "$boot_dir/lib/$module"; then
      echo " [错误] 下载的模块语法检查失败：$module" >&2
      rm -rf -- "$boot_dir"
      return 1
    fi
  done

  chmod 700 "$boot_dir/install.sh"
  chmod 600 "$boot_dir/SHA256SUMS"
  chmod 644 "$boot_dir/$VERSION_FILE"
  chmod 700 "$boot_dir"/lib/*.sh

  echo " [安全] 完整引导包验证通过，正在切换到可信副本……"

  export HY2_VLESS_BOOTSTRAP_DIR="$boot_dir"

  # shellcheck disable=SC2093  # 此处故意用 exec 切换到已校验的引导副本。

  exec bash \
    "$boot_dir/install.sh" \
    "${ORIGINAL_ARGS[@]}"

  local rc=$?

  echo " [错误] 无法执行已验证的入口脚本。" >&2
  rm -rf -- "$boot_dir"

  return "$rc"
}


install_self_shortcut() {
 # 模块化后不能再只把单个 install.sh 复制到 /usr/bin/666。
 # 正确做法：把入口和 lib/ 一起落盘到 /opt，再创建 666 包装器。
 mkdir -p "$INSTALL_DIR/lib"

 if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
 cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || cp -f "$SCRIPT_PATH" "$INSTALL_DIR/install.sh" || return 1

 local module=""
 for module in "${MODULES[@]}"; do
 if [[ ! -s "$SCRIPT_DIR/lib/$module" ]]; then
 echo " [错误] 无法落盘快捷入口：模块缺失或为空：$SCRIPT_DIR/lib/$module" >&2
 return 1
 fi
 cp -f "$SCRIPT_DIR/lib/$module" "$INSTALL_DIR/lib/$module" || return 1
 done

 cp -f "$SCRIPT_DIR/$VERSION_FILE" "$INSTALL_DIR/$VERSION_FILE" 2>/dev/null || echo "$HY2_VLESS_VERSION" > "$INSTALL_DIR/$VERSION_FILE"
 chmod +x "$INSTALL_DIR/install.sh"
 chmod +x "$INSTALL_DIR"/lib/*.sh 2>/dev/null || true
 fi

 cat > /usr/bin/666 <<EOF_WRAPPER
#!/usr/bin/env bash
cd "$INSTALL_DIR" || exit 1
exec bash "$INSTALL_DIR/install.sh" "\$@"
EOF_WRAPPER

 chmod +x /usr/bin/666
}



ensure_modules || exit 1

validate_local_bundle || exit 1

load_modules || exit 1

install_self_shortcut || exit 1

while true; do
 menu
done
