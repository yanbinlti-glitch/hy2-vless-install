#!/usr/bin/env bash
# shellcheck shell=bash


# 物理地基校验：确保极限环境下目录结构绝对存在
ensure_foundation() {
    if [[ ! -d "/opt/hy2_tmp" ]]; then
        mkdir -p "/opt/hy2_tmp" >/dev/null 2>&1
        chmod 755 "/opt/hy2_tmp" >/dev/null 2>&1
    fi
    # 彻底清理可能导致解压失败的旧版僵尸文件
    rm -rf /opt/hy2_tmp/sing-box* 2>/dev/null
}

ensure_foundation
HY2_REPO_OWNER="${HY2_REPO_OWNER:-yanbinlti-glitch}"
HY2_REPO_NAME="${HY2_REPO_NAME:-hy2-vless-install}"
HY2_REPO_BRANCH="${HY2_REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/hy2-vless-install}"

get_raw_base() {
    echo "https://raw.githubusercontent.com/${HY2_REPO_OWNER}/${HY2_REPO_NAME}/${HY2_REPO_BRANCH}"
}

get_github_latest_commit_sha() {
    local api json sha
    api="${HY2_VLESS_GITHUB_API:-https://api.github.com/repos/${HY2_REPO_OWNER}/${HY2_REPO_NAME}/commits/${HY2_REPO_BRANCH}}"

    if command -v curl >/dev/null 2>&1; then
        json="$(curl -fsSL --connect-timeout 10 --retry 2 "$api" 2>/dev/null)"
    elif command -v wget >/dev/null 2>&1; then
        json="$(wget -q --timeout=10 --tries=2 -O- "$api" 2>/dev/null)"
    else
        return 1
    fi

    sha="$(printf '%s\n' "$json" | grep -m1 '"sha"' | sed -E 's/.*"sha"[[:space:]]*:[[:space:]]*"([0-9a-f]{40})".*/\1/')"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
    echo "$sha"
}

get_update_base() {
    local ref="${HY2_VLESS_UPDATE_REF:-}"
    if [[ -n "$ref" ]]; then
        echo "https://raw.githubusercontent.com/${HY2_REPO_OWNER}/${HY2_REPO_NAME}/${ref}"
        return 0
    fi
    get_raw_base
}

get_local_version() {
    cat "${INSTALL_DIR}/VERSION" 2>/dev/null \
        || cat "${SCRIPT_DIR:-.}/VERSION" 2>/dev/null \
        || echo "dev"
}

download_update_file() {
    local url="$1"
    local out="$2"

    mkdir -p "$(dirname "$out")"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --retry 3 "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 --tries=3 -O "$out" "$url"
    else
        red " [错误] 未检测到 curl 或 wget。"
        return 1
    fi
}

get_remote_version() {
    local base="$1"
    local tmp_ver

    tmp_ver="$(mktemp /tmp/hy2-vless-version.XXXXXX)" || return 1

    if download_update_file "$base/VERSION" "$tmp_ver" >/dev/null 2>&1; then
        head -n1 "$tmp_ver" | tr -d '[:space:]'
        rm -f "$tmp_ver"
        return 0
    fi

    rm -f "$tmp_ver"
    return 1
}

version_gt() {
    local a="$1"
    local b="$2"

    [[ -z "$a" || "$a" == "dev" ]] && return 1
    [[ -z "$b" || "$b" == "dev" ]] && return 0
    [[ "$a" == "$b" ]] && return 1

    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}

pause_after_update() {
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回菜单...${PLAIN}"
    read -r _ || true
}

verify_update_checksums() {
    local tmp_dir="$1"
    local sums_file="$tmp_dir/SHA256SUMS"
    local expected target actual failed=0

    if [[ ! -s "$sums_file" ]]; then
        red " [错误] 未找到 SHA256SUMS，已停止更新。"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        red " [错误] 当前系统缺少 sha256sum，无法校验更新文件。"
        return 1
    fi

    yellow " 正在校验更新文件完整性..."

    while read -r expected target _; do
        [[ -z "$expected" || -z "$target" ]] && continue
        [[ "$expected" =~ ^# ]] && continue

        target="${target#./}"

        case "$target" in
            install.sh|VERSION|lib/*.sh) ;;
            *) continue ;;
        esac

        if [[ ! -f "$tmp_dir/$target" ]]; then
            red " [错误] 校验失败，文件缺失: $target"
            failed=1
            continue
        fi

        actual="$(sha256sum "$tmp_dir/$target" | awk '{print $1}')"

        if [[ "$actual" != "$expected" ]]; then
            red " [错误] 校验失败: $target"
            red "        期望: $expected"
            red "        实际: $actual"
            failed=1
        fi
    done < "$sums_file"

    [[ "$failed" -eq 0 ]]
}

self_update() {
    local base tmp_dir local_ver remote_ver bak_dir install_dir confirm_update m
    local -a update_modules fallback_modules

    fallback_modules=(
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

    clear
    print_line
    green " 检查 / 在线更新脚本 "
    print_line
    echo ""

    base="$(get_update_base)"
    local_ver="$(get_local_version)"
    remote_ver="$(get_remote_version "$base" 2>/dev/null || true)"

    yellow " 当前版本: ${local_ver}"
    yellow " 远程版本: ${remote_ver:-获取失败}"
    yellow " 更新源地址: ${base}"
    echo ""

    if [[ -z "$remote_ver" ]]; then
        red " [错误] 无法获取远程版本。"
        pause_after_update
        return 1
    fi

    if ! version_gt "$remote_ver" "$local_ver"; then
        green " 当前已经是最新版本。"
        pause_after_update
        return 0
    fi

    printf "%b" " ${LIGHT_YELLOW} ▶ 检测到新版本，是否更新？(y/n) [默认: y]: ${PLAIN}"
    read -r confirm_update || confirm_update="y"
    [[ -z "$confirm_update" ]] && confirm_update="y"

    if [[ "$confirm_update" != "y" && "$confirm_update" != "Y" ]]; then
        yellow " 已取消更新。"
        pause_after_update
        return 0
    fi

    tmp_dir="$(mktemp -d /tmp/hy2-vless-update.XXXXXX)" || {
        red " [错误] 无法创建临时目录。"
        pause_after_update
        return 1
    }

    mkdir -p "$tmp_dir/lib"

    yellow " 正在下载远程版本与校验清单..."

    if ! download_update_file "$base/VERSION" "$tmp_dir/VERSION"; then
        echo "$remote_ver" > "$tmp_dir/VERSION"
    fi

    if ! download_update_file "$base/SHA256SUMS" "$tmp_dir/SHA256SUMS"; then
        red " [错误] SHA256SUMS 下载失败，已停止更新。"
        rm -rf "$tmp_dir"
        pause_after_update
        return 1
    fi

    yellow " 正在下载新版入口脚本..."

    if ! download_update_file "$base/install.sh" "$tmp_dir/install.sh"; then
        red " [错误] install.sh 下载失败。"
        rm -rf "$tmp_dir"
        pause_after_update
        return 1
    fi

    while read -r m; do
        m="${m#lib/}"
        [[ -n "$m" ]] && update_modules+=("$m")
    done < <(awk '$2 ~ /^lib\/.*\.sh$/ {print $2}' "$tmp_dir/SHA256SUMS")

    if [[ "${#update_modules[@]}" -eq 0 ]]; then
        yellow " [提示] SHA256SUMS 未读取到模块列表，回退使用内置模块列表。"
        update_modules=("${fallback_modules[@]}")
    fi

    yellow " 正在下载新版模块..."

    for m in "${update_modules[@]}"; do
        if ! download_update_file "$base/lib/$m" "$tmp_dir/lib/$m"; then
            red " [错误] 模块下载失败: $m"
            rm -rf "$tmp_dir"
            pause_after_update
            return 1
        fi
    done

    if ! verify_update_checksums "$tmp_dir"; then
        red " [错误] 更新文件完整性校验失败，已停止更新。"
        rm -rf "$tmp_dir"
        pause_after_update
        return 1
    fi

    yellow " 正在执行语法检查..."

    if ! bash -n "$tmp_dir/install.sh"; then
        red " [错误] install.sh 语法检查失败。"
        rm -rf "$tmp_dir"
        pause_after_update
        return 1
    fi

    for m in "$tmp_dir"/lib/*.sh; do
        if ! bash -n "$m"; then
            red " [错误] 模块语法检查失败: $(basename "$m")"
            rm -rf "$tmp_dir"
            pause_after_update
            return 1
        fi
    done

    install_dir="$INSTALL_DIR"
    bak_dir="${install_dir}.bak.$(date +%F-%H%M%S)"

    yellow " 正在备份当前版本..."
    mkdir -p "$install_dir"

    if [[ -d "$install_dir" ]]; then
        cp -a "$install_dir" "$bak_dir" 2>/dev/null || true
    fi

    yellow " 正在覆盖安装新版脚本..."

    mkdir -p "$install_dir/lib"
    find "$install_dir/lib" -maxdepth 1 -type f -name '*.sh' -delete 2>/dev/null || true

    if ! cp -f "$tmp_dir/install.sh" "$install_dir/install.sh" \
        || ! cp -f "$tmp_dir"/lib/*.sh "$install_dir/lib/" \
        || ! cp -f "$tmp_dir/VERSION" "$install_dir/VERSION" \
        || ! cp -f "$tmp_dir/SHA256SUMS" "$install_dir/SHA256SUMS"; then

        red " [错误] 覆盖安装失败，正在回滚。"

        if [[ -d "$bak_dir" ]]; then
            rm -rf "$install_dir"
            mv -f "$bak_dir" "$install_dir"
        fi

        rm -rf "$tmp_dir"
        pause_after_update
        return 1
    fi

    chmod +x "$install_dir/install.sh" "$install_dir"/lib/*.sh 2>/dev/null || true

    cat > /usr/bin/666 <<EOF_WRAPPER
#!/usr/bin/env bash
cd "$install_dir" || exit 1
exec bash "$install_dir/install.sh" "\$@"
EOF_WRAPPER

    chmod +x /usr/bin/666
    rm -rf "$tmp_dir"

    HY2_VLESS_VERSION="$remote_ver"
    export HY2_VLESS_VERSION

    green " [✔] 更新完成: ${local_ver} -> ${remote_ver}"
    yellow " [提示] 3 秒后自动重启新版面板..."
    sleep 3

    if [[ -f "$install_dir/install.sh" ]]; then
        exec bash "$install_dir/install.sh"
    fi

    red " [错误] 自动重启新版面板失败，请手动运行: 666"
    pause_after_update
    return 1
}
