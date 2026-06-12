#!/usr/bin/env bash
# shellcheck shell=bash

#  4. 自动换源、依赖环境检查、核心拉取与节点探测
# =================================================================
run_with_timeout() {
    local seconds="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" bash -c "$*"
    else
        bash -c "$*"
    fi
}

run_logged_with_timeout() {
    local seconds="$1"
    local logfile="$2"
    shift 2
    : > "$logfile"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" bash -c "$*" 2>&1 | tee -a "$logfile"
        return ${PIPESTATUS[0]}
    else
        bash -c "$*" 2>&1 | tee -a "$logfile"
        return ${PIPESTATUS[0]}
    fi
}

pkg_update_fast_cmd() {
    case "$SYSTEM" in
        Alpine)
            echo "apk update"
            ;;
        Debian|Ubuntu)
            echo "apt-get -o Acquire::http::Timeout=8 -o Acquire::https::Timeout=8 -o Acquire::Retries=0 update"
            ;;
        CentOS|Fedora)
            echo "yum -y --setopt=timeout=8 makecache"
            ;;
        *)
            echo "$PKG_UPDATE"
            ;;
    esac
}

switch_system_source_auto() {
    yellow "  默认软件源响应异常，正在自动备份并切换至 Aliyun 镜像源..."
    if [[ $SYSTEM == "Alpine" ]]; then
        cp /etc/apk/repositories /etc/apk/repositories.bak.$(date +%F-%H%M%S) || true
        sed -i 's#https\?://dl-cdn.alpinelinux.org#https://mirrors.aliyun.com#g; s#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories
    elif [[ $SYSTEM == "Debian" ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F-%H%M%S) 2>/dev/null || true
        cp -r /etc/apt/sources.list.d /etc/apt/sources.list.d.bak.$(date +%F-%H%M%S) 2>/dev/null || true
        sed -i 's#http://deb.debian.org#https://mirrors.aliyun.com#g; s#https://deb.debian.org#https://mirrors.aliyun.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
        sed -i 's#http://security.debian.org/debian-security#https://mirrors.aliyun.com/debian-security#g; s#https://security.debian.org/debian-security#https://mirrors.aliyun.com/debian-security#g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
    elif [[ $SYSTEM == "Ubuntu" ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F-%H%M%S) 2>/dev/null || true
        cp -r /etc/apt/sources.list.d /etc/apt/sources.list.d.bak.$(date +%F-%H%M%S) 2>/dev/null || true
        sed -i 's#http://[a-zA-Z0-9.-]*archive.ubuntu.com#https://mirrors.aliyun.com#g; s#https://[a-zA-Z0-9.-]*archive.ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
        sed -i 's#http://security.ubuntu.com#https://mirrors.aliyun.com#g; s#https://security.ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
        cp -r /etc/yum.repos.d /etc/yum.repos.d.bak.$(date +%F-%H%M%S) || true
        sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/*.repo || true
        sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/*.repo || true
        sed -i 's#mirror.centos.org#mirrors.aliyun.com#g; s#download.fedoraproject.org#mirrors.aliyun.com#g' /etc/yum.repos.d/*.repo || true
    fi
    green "  [✔] 镜像源切换完成。"
}

auto_source_guard() {
    echo ""
    print_line
    green "                  软件源智能探测与防卡死保护                  "
    print_line
    echo ""
    yellow "  正在限时检测默认软件源连通性，异常时将自动切换镜像源..."

    local probe_cmd
    probe_cmd="$(pkg_update_fast_cmd)"
    if run_logged_with_timeout 35 /tmp/singbox_source_probe.log "$probe_cmd"; then
        green "  [✔] 默认软件源可用，继续保留系统当前源。"
        SOURCE_UPDATED=1
        return 0
    fi

    yellow "  默认软件源检测失败或超时，已触发自动换源兜底。"
    switch_system_source_auto

    if run_logged_with_timeout 45 /tmp/singbox_source_probe.log "$probe_cmd"; then
        green "  [✔] 镜像源刷新成功。"
        SOURCE_UPDATED=1
        return 0
    fi

    red "  [错误] 镜像源刷新仍失败，最近日志如下："
    tail -n 30 /tmp/singbox_source_probe.log 2>/dev/null || true
    return 1
}

print_dep_status() {
    local name="$1"
    local cmd="$2"
    local tip="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
        green "    ✓ $name"
    else
        yellow "    · $name  ${tip}"
    fi
}

change_system_source() {
    auto_source_guard
}

check_env() {
    clear
    echo ""
    print_line
    green "             系统依赖检查与 Sing-box 核心前置拉取            "
    print_line
    echo ""
    green "  当前操作系统: $SYSTEM"
    echo ""
    purple "  本步骤会自动完成：软件源探测、依赖补全、二维码组件、Sing-box 核心检查。"

    SOURCE_UPDATED=0
    auto_source_guard || { red " [错误] 软件源刷新失败，请检查 VPS 网络连接！"; exit 1; }

    echo ""
    print_line
    green "                        前置组件巡检                        "
    print_line
    print_dep_status "网络拉取工具 curl" "curl" "待安装"
    print_dep_status "备用下载工具 wget" "wget" "待安装"
    print_dep_status "端口检测工具 ss" "ss" "待安装"
    print_dep_status "防火墙工具 iptables" "iptables" "待安装"
    print_dep_status "JSON 处理器 jq" "jq" "待安装"
    print_dep_status "证书工具 openssl" "openssl" "待安装"
    print_dep_status "二维码工具 qrencode" "qrencode" "待安装，用于订阅二维码"
    print_dep_status "Nginx 订阅分发" "nginx" "待安装"

    echo ""
    yellow "  正在校准系统时钟 (防御 TLS 时钟偏移瘫痪)..."
    local date_str=$(curl -sI -m 3 https://google.com 2>/dev/null | grep -i Date | cut -d' ' -f3-6)
    [[ -z "$date_str" ]] && date_str=$(curl -sI -m 3 https://cloudflare.com 2>/dev/null | grep -i Date | cut -d' ' -f3-6)
    [[ -n "$date_str" ]] && date -s "${date_str}Z" || true
    green "  [✔] 时间校准步骤完成。"
    
    local cmds=("curl" "wget" "sudo" "ss" "iptables" "python3" "openssl" "socat" "qrencode" "jq" "tar" "nginx")
    local missing=0

    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then missing=1; fi
    done

    if [[ $SYSTEM == "Alpine" ]]; then
        if ! apk info -e libc6-compat >/dev/null 2>&1 || ! apk info -e gcompat >/dev/null 2>&1; then
            missing=1
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        echo ""
        yellow "  发现缺失组件，正在自动补全。安装日志将实时显示，不再静默隐藏。"
        if [[ "${SOURCE_UPDATED:-0}" -ne 1 ]]; then
            auto_source_guard || { red " [错误] 软件源刷新失败！"; exit 1; }
        fi
        
        if [[ $SYSTEM == "Alpine" ]]; then
            run_with_timeout 180 "$PKG_INSTALL curl wget sudo procps iptables ip6tables iproute2 python3 openssl socat libqrencode-tools jq coreutils nginx tar libc6-compat gcompat" || run_with_timeout 180 "$PKG_INSTALL curl wget sudo procps iptables ip6tables iproute2 python3 openssl socat qrencode jq coreutils nginx tar libc6-compat gcompat" || { red " [错误] 依赖安装失败！"; exit 1; }
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            $PKG_INSTALL epel-release || true
            run_with_timeout 240 "$PKG_INSTALL curl wget sudo procps iptables iptables-services iproute python3 openssl socat qrencode jq coreutils nginx tar" || { red " [错误] 依赖安装失败！"; exit 1; }
        else
            export DEBIAN_FRONTEND=noninteractive
            run_with_timeout 240 "apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y install curl wget sudo procps iptables-persistent netfilter-persistent iproute2 python3 openssl socat qrencode jq coreutils nginx tar" || { red " [错误] 依赖安装失败！"; exit 1; }
        fi
        echo ""
        if ! command -v logrotate >/dev/null 2>&1; then
            $PKG_INSTALL logrotate >/dev/null 2>&1 || true
        fi

        # 强制唤醒 Alpine 定时任务守护进程，防止 logrotate 变植物人
        if [[ $SYSTEM == "Alpine" ]]; then
            rc-update add crond default >/dev/null 2>&1 || true
            rc-service crond start >/dev/null 2>&1 || true
        fi
        green "  [✔] 所有前置依赖补全完成，二维码组件 qrencode 已纳入安装。"
    else
        echo ""
        green "  [✔] 所有前置依赖检查通过，二维码组件已就绪。"
    fi

    ensure_singbox_core || exit 1
    sleep 1
}

has_hy2=0
has_vless=0
check_installed_nodes() {
    has_hy2=0
    has_vless=0
    if [[ -f /etc/sing-box/config.json ]]; then
        if jq -e '.inbounds[] | select(.tag=="hy2-in")' /etc/sing-box/config.json >/dev/null 2>&1; then has_hy2=1; fi
        if jq -e '.inbounds[] | select(.tag=="vless-in")' /etc/sing-box/config.json >/dev/null 2>&1; then has_vless=1; fi
    fi
}

