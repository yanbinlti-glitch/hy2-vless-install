#!/usr/bin/env bash
# shellcheck shell=bash

HY2_REPO_OWNER="${HY2_REPO_OWNER:-yanbinlti-glitch}"
HY2_REPO_NAME="${HY2_REPO_NAME:-hy2-vless-install}"
HY2_REPO_BRANCH="${HY2_REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/hy2-vless-install}"

get_local_version() { cat "${INSTALL_DIR}/VERSION" 2>/dev/null || cat "${SCRIPT_DIR:-.}/VERSION" 2>/dev/null || echo "dev"; }

download_update_file() {
    local url="$1"; local out="$2"; mkdir -p "$(dirname "$out")"
    if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 15 --retry 3 "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then wget -q --timeout=15 --tries=3 -O "$out" "$url"
    else return 1; fi
}

self_update() {
    local base="https://raw.githubusercontent.com/${HY2_REPO_OWNER}/${HY2_REPO_NAME}/${HY2_REPO_BRANCH}"
    local local_ver tmp_dir install_dir bak_dir m
    local -a update_modules=("00_ui.sh" "01_system.sh" "02_service_firewall.sh" "03_env_core.sh" "04_install_nodes.sh" "05_subscription.sh" "06_panel_tools.sh" "07_menu.sh" "08_update.sh")

    clear
    green " ──────────────────────────────────────────────────────────"
    green " 检查 / 在线更新脚本 (极速强拉无哈希版) "
    green " ──────────────────────────────────────────────────────────"
    echo ""

    local_ver="$(get_local_version)"
    yellow " 当前版本: ${local_ver}"
    yellow " 更新源地址: ${base}"
    
    printf "%b" " ${LIGHT_YELLOW} ▶ 是否拉取最新代码并强制覆盖更新？(y/n) [默认: y]: ${PLAIN}"
    read -r confirm_update || confirm_update="y"
    [[ -z "$confirm_update" ]] && confirm_update="y"

    if [[ "$confirm_update" != "y" && "$confirm_update" != "Y" ]]; then
        yellow " 已取消更新。"; echo ""; printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回...${PLAIN}"; read -r _ || true; return 0
    fi

    tmp_dir="$(mktemp -d /tmp/hy2-vless-update.XXXXXX)"; mkdir -p "$tmp_dir/lib"

    yellow " 正在绕过哈希限制，直接强拉远程模块..."
    download_update_file "$base/VERSION" "$tmp_dir/VERSION" || echo "latest" > "$tmp_dir/VERSION"
    download_update_file "$base/install.sh" "$tmp_dir/install.sh" || { red " [错误] install.sh 下载失败。"; read -p " ▶ 按回车键返回..." temp; return 1; }

    for m in "${update_modules[@]}"; do
        download_update_file "$base/lib/$m" "$tmp_dir/lib/$m" || { red " [错误] 模块下载失败: $m"; read -p " ▶ 按回车键返回..." temp; return 1; }
    done

    install_dir="$INSTALL_DIR"
    bak_dir="${install_dir}.bak.$(date +%F-%H%M%S)"
    mkdir -p "$install_dir/lib"
    [[ -d "$install_dir" ]] && cp -a "$install_dir" "$bak_dir" 2>/dev/null || true

    if [[ -n "$HY2_CLONE_NAME" ]]; then
        yellow " 正在对分身 $HY2_CLONE_NAME 实施物理隔离转换..."
        apply_clone_transform "$HY2_CLONE_NAME" "$tmp_dir"
    fi

    if ! cp -f "$tmp_dir/install.sh" "$install_dir/install.sh" || ! cp -f "$tmp_dir"/lib/*.sh "$install_dir/lib/" || ! cp -f "$tmp_dir/VERSION" "$install_dir/VERSION"; then
        red " [错误] 覆盖失败，已恢复原版。"; read -p " ▶ 按回车键返回..." temp; return 1
    fi

    chmod +x "$install_dir/install.sh" "$install_dir"/lib/*.sh 2>/dev/null || true
    cat > /usr/bin/666 <<EOF_WRAPPER
#!/usr/bin/env bash
cd "$install_dir" || exit 1
exec bash "$install_dir/install.sh" "\$@"
EOF_WRAPPER
    chmod +x /usr/bin/666; rm -rf "$tmp_dir"

    green " [✔] 无哈希极速热更新完成！"
    yellow " [提示] 3 秒后自动重启新版面板..."
    sleep 3; exec bash "$install_dir/install.sh"
}
