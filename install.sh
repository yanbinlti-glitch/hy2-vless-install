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
# V1.8.3 全局防并发排他锁 (Mutex Lock)
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
  local api=""
  local response=""
  local commit_sha=""

  if [[ -n "${HY2_VLESS_RAW_BASE:-}" ]]; then
    if [[ "${HY2_VLESS_ALLOW_CUSTOM_SOURCE:-0}" != "1" ]]
    then
      echo " [错误] 检测到自定义模块下载源，但未明确允许。" >&2
      echo " [提示] 只有在信任该源时才设置：" >&2
      echo " HY2_VLESS_ALLOW_CUSTOM_SOURCE=1" >&2
      return 1
    fi

    case "$HY2_VLESS_RAW_BASE" in
      https://*)
        REPO_RAW_BASE="${HY2_VLESS_RAW_BASE%/}"
        export REPO_RAW_BASE

        echo " [警告] 当前使用显式允许的自定义下载源。" >&2
        return 0
        ;;

      *)
        echo " [错误] 自定义下载源必须使用 HTTPS。" >&2
        return 1
        ;;
    esac
  fi

  api="$(
    printf \
      'https://api.github.com/repos/%s/%s/commits/%s' \
      "$REPO_OWNER" \
      "$REPO_NAME" \
      "$REPO_BRANCH"
  )"

  response="$(download_text "$api")" || {
    echo " [错误] 无法获取 GitHub 分支提交信息。" >&2
    return 1
  }

  commit_sha="$(
    printf '%s\n' "$response" |
      grep -m1 -E \
        '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' |
      sed -E \
        's/.*"sha"[[:space:]]*:[[:space:]]*"([0-9a-f]{40})".*/\1/'
  )"

  if [[ ! "$commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo " [错误] GitHub API 未返回有效的提交 SHA。" >&2
    return 1
  fi

  REPO_RAW_BASE="$(
    printf \
      'https://raw.githubusercontent.com/%s/%s/%s' \
      "$REPO_OWNER" \
      "$REPO_NAME" \
      "$commit_sha"
  )"

  export REPO_RAW_BASE

  echo " [安全] 本次引导已锁定不可变提交：$commit_sha"
}

verify_bootstrap_checksums() {
  local root="$1"
  local manifest="$root/SHA256SUMS"
  local target=""
  local expected=""
  local actual=""
  local module=""
  local -a targets=()

  if [[ ! -s "$manifest" ]]; then
    echo " [错误] 缺少有效的 SHA256SUMS。" >&2
    return 1
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    echo " [错误] 系统缺少 sha256sum，无法验证引导文件。" >&2
    return 1
  fi

  targets=(
    "install.sh"
    "$VERSION_FILE"
  )

  for module in "${MODULES[@]}"; do
    targets+=("lib/$module")
  done

  for target in "${targets[@]}"; do
    if [[ ! -f "$root/$target" ]]; then
      echo " [错误] 引导文件缺失：$target" >&2
      return 1
    fi

    expected="$(
      awk \
        -v target="$target" \
        '
          $2 == target || $2 == "./" target {
            print $1
            exit
          }
        ' \
        "$manifest"
    )"

    if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
      echo " [错误] 校验清单缺少有效记录：$target" >&2
      return 1
    fi

    actual="$(
      sha256sum "$root/$target" |
        awk '{print tolower($1)}'
    )"

    expected="${expected,,}"

    if [[ "$actual" != "$expected" ]]; then
      echo " [错误] SHA-256 校验失败：$target" >&2
      echo " [期望] $expected" >&2
      echo " [实际] $actual" >&2
      return 1
    fi
  done

  echo " [安全] 首次引导文件 SHA-256 校验全部通过。"
}

validate_local_bundle() {
  local module=""

  if [[ ! -f "$SCRIPT_DIR/install.sh" ]]; then
    echo " [错误] 找不到入口文件：$SCRIPT_DIR/install.sh" >&2
    return 1
  fi

  if ! bash -n "$SCRIPT_DIR/install.sh"; then
    echo " [错误] install.sh 语法检查失败。" >&2
    return 1
  fi

  for module in "${MODULES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/lib/$module" ]]; then
      echo " [错误] 模块文件缺失：$module" >&2
      return 1
    fi

    if ! bash -n "$SCRIPT_DIR/lib/$module"; then
      echo " [错误] 模块语法检查失败：$module" >&2
      return 1
    fi
  done

  echo " [安全] 入口和全部模块语法检查通过。"
}

ensure_modules() {
  local missing=0
  local module=""
  local url=""
  local boot_dir=""

  for module in "${MODULES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/lib/$module" ]]; then
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

  if ! download_file \
    "$REPO_RAW_BASE/SHA256SUMS" \
    "$boot_dir/SHA256SUMS"
  then
    echo " [错误] SHA256SUMS 下载失败。" >&2
    rm -rf -- "$boot_dir"
    return 1
  fi

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

  if ! verify_bootstrap_checksums "$boot_dir"; then
    rm -rf -- "$boot_dir"
    return 1
  fi

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
    cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || cp -f "$SCRIPT_PATH" "$INSTALL_DIR/install.sh"
    cp -f "$SCRIPT_DIR"/lib/*.sh "$INSTALL_DIR/lib/"
    cp -f "$SCRIPT_DIR/$VERSION_FILE" "$INSTALL_DIR/$VERSION_FILE" 2>/dev/null || echo "$HY2_VLESS_VERSION" > "$INSTALL_DIR/$VERSION_FILE"
cp -f "$SCRIPT_DIR/SHA256SUMS" "$INSTALL_DIR/SHA256SUMS" 2>/dev/null || true
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

for module in "${MODULES[@]}"; do
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/$module"
done

install_self_shortcut

export HY2_INSTANCE_ID="1"
export HY2_INSTANCE_SUFFIX=""

clear
printf "
[1;36m==================================================================================[0m
"
printf "       👥 请选择要管理的 Sing-box 实例分身        
"
printf "[1;36m==================================================================================[0m
"
printf "    [1;32m[1][0m 部署/管理 [1;33m实例本尊[0m (Instance 1, 默认环境)
"
printf "    [1;32m[2][0m 部署/管理 [1;35m实例分身[0m (Instance 2, 完全独立的端口与进程)
"
printf "  [1;33m▶[0m 请输入选项 [1-2] (默认1): "
read instance_choice
if [[ "$instance_choice" == "2" ]]; then
    export HY2_INSTANCE_ID="2"
    export HY2_INSTANCE_SUFFIX="_2"
fi

while true; do
  menu
done
