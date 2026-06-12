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
#  1. 现代化极简 UI 色彩库 & 全局中断防崩溃保护
# =================================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PURPLE="\033[35m"
CYAN="\033[36m"

LIGHT_RED="\033[1;31m"
LIGHT_GREEN="\033[1;32m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_PURPLE="\033[1;35m"
LIGHT_CYAN="\033[1;36m"
PLAIN="\033[0m"

red()    { echo -e "${LIGHT_RED}$1${PLAIN}"; }
green()  { echo -e "${LIGHT_GREEN}$1${PLAIN}"; }
yellow() { echo -e "${LIGHT_YELLOW}$1${PLAIN}"; }
purple() { echo -e "${LIGHT_PURPLE}$1${PLAIN}"; }

print_line() {
    green " ──────────────────────────────────────────────────────────"
}

trap 'echo -e "\n\n ${LIGHT_RED}[警告] 检测到强行中断，脚本已安全退出。${PLAIN}"; exit 1' INT TERM

