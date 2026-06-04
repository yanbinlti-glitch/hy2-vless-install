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
REPO_RAW_BASE="${HY2_VLESS_RAW_BASE:-https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main}"
INSTALL_DIR="${HY2_VLESS_INSTALL_DIR:-/opt/hy2-vless-install}"

MODULES=(
  "00_ui.sh"
  "01_system.sh"
  "02_service_firewall.sh"
  "03_env_core.sh"
  "04_install_nodes.sh"
  "05_subscription.sh"
  "06_panel_tools.sh"
  "07_menu.sh"
)

download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 --tries=2 -O "$dest" "$url"
    else
        echo " [错误] 未找到 curl 或 wget，无法自动下载模块。" >&2
        return 1
    fi
}

ensure_modules() {
    local missing=0
    local m

    for m in "${MODULES[@]}"; do
        [[ -f "$SCRIPT_DIR/lib/$m" ]] || missing=1
    done

    [[ "$missing" -eq 0 ]] && return 0

    local boot_dir
    boot_dir=$(mktemp -d /tmp/hy2-vless-install.XXXXXX) || return 1
    mkdir -p "$boot_dir/lib"

    echo " [提示] 未检测到本地 lib/ 模块，正在从 GitHub 拉取模块文件..."

    for m in "${MODULES[@]}"; do
        local url="${REPO_RAW_BASE}/lib/${m}"
        if ! download_file "$url" "$boot_dir/lib/$m"; then
            echo " [错误] 模块下载失败：$url" >&2
            return 1
        fi
    done

    cp -f "$SCRIPT_PATH" "$boot_dir/install.sh" 2>/dev/null || true
    SCRIPT_DIR="$boot_dir"
    return 0
}

install_self_shortcut() {
    # 模块化后不能再只把单个 install.sh 复制到 /usr/bin/666。
    # 正确做法：把入口和 lib/ 一起落盘到 /opt，再创建 666 包装器。
    mkdir -p "$INSTALL_DIR/lib"

    if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || cp -f "$SCRIPT_PATH" "$INSTALL_DIR/install.sh"
        cp -f "$SCRIPT_DIR"/lib/*.sh "$INSTALL_DIR/lib/"
        chmod +x "$INSTALL_DIR/install.sh"
    fi

    cat > /usr/bin/666 <<EOF
#!/usr/bin/env bash
bash "$INSTALL_DIR/install.sh" "\$@"
EOF
    chmod +x /usr/bin/666
}

ensure_modules || exit 1

for module in "${MODULES[@]}"; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$module"
done

install_self_shortcut

while true; do
    menu
done
