#!/usr/bin/env bash
# shellcheck shell=bash

#  2. 基础系统判定与快捷命令覆写
# =================================================================
[[ $EUID -ne 0 ]] && red " [错误] 请在 root 用户下运行此脚本！" && exit 1

# 快捷命令与多文件安装目录由入口 install.sh 统一处理。
# 这里仅负责系统识别、包管理器变量、公共工具函数。

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    SYS=$ID
else
    SYS="$(uname -s)"
fi

case $(echo "$SYS" | tr '[:upper:]' '[:lower:]') in
    alpine)
        SYSTEM="Alpine"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        ;;
    debian)
        SYSTEM="Debian"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get -y install"
        ;;
    ubuntu)
        SYSTEM="Ubuntu"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get -y install"
        ;;
    centos|rhel|almalinux|rocky)
        SYSTEM="CentOS"
        PKG_UPDATE="yum -y update"
        PKG_INSTALL="yum -y install"
        ;;
    fedora)
        SYSTEM="Fedora"
        PKG_UPDATE="yum -y update"
        PKG_INSTALL="yum -y install"
        ;;
    *)
        red " [错误] 目前暂不支持您的 VPS 操作系统！" && exit 1
        ;;
esac

PUBLIC_IP=""
valid_ip_literal() {
    python3 - "$1" <<'PYIP' >/dev/null 2>&1
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1].strip())
except Exception:
    sys.exit(1)
PYIP
}

realip() {
    if [[ -n "$PUBLIC_IP" ]] && valid_ip_literal "$PUBLIC_IP"; then
        return
    fi
    local ip=""
    local endpoints4=("https://api.ipify.org" "https://ifconfig.me/ip" "https://ip.sb")
    local endpoints6=("https://api64.ipify.org" "https://ifconfig.me/ip" "https://ip.sb")

    if ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
        for ep in "${endpoints4[@]}"; do
            ip=$(curl -fsS4m4 "$ep" -k 2>/dev/null | head -n1 | tr -d '[:space:]')
            if valid_ip_literal "$ip"; then break; fi
            ip=""
        done
    fi
    if [[ -z "$ip" ]]; then
        for ep in "${endpoints6[@]}"; do
            ip=$(curl -fsS6m4 "$ep" -k 2>/dev/null | head -n1 | tr -d '[:space:]')
            if valid_ip_literal "$ip"; then break; fi
            ip=""
        done
    fi
    if [[ -z "$ip" ]]; then
        red " [错误] 无法获取本机的公网 IP，请检查 VPS 网络连接！"
        exit 1
    fi
    PUBLIC_IP="$ip"
}

gen_random_str() {
    local len=$1
    head -c 32 /dev/urandom | base64 | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c "$len"
}

