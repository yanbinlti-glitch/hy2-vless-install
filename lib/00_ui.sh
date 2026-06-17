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

# HY2_QUIET_PROGRESS_V2_BEGIN
# 静默日志 + 中文进度助手。
# 默认隐藏底层命令输出，只显示中文进度、绿色成功勾、红色失败叉。
# 调试时可使用：HY2_SHOW_LOG=1 bash install.sh
: "${HY2_SHOW_LOG:=0}"
: "${HY2_LOG_DIR:=/var/log/hy2-vless-install}"

_hy2_color_defaults() {
  : "${LIGHT_RED:=\033[1;31m}"
  : "${LIGHT_GREEN:=\033[1;32m}"
  : "${LIGHT_YELLOW:=\033[1;33m}"
  : "${LIGHT_CYAN:=\033[1;36m}"
  : "${PLAIN:=\033[0m}"
}

hy2_log_dir_prepare() {
  _hy2_color_defaults

  local dir="${HY2_LOG_DIR:-/var/log/hy2-vless-install}"

  case "$dir" in
    /*) ;;
    *) dir="${TMPDIR:-/tmp}/hy2-vless-install" ;;
  esac

  if [[ -L "$dir" ]]; then
    dir="${TMPDIR:-/tmp}/hy2-vless-install"
  fi

  if ! install -d -m 700 "$dir" 2>/dev/null; then
    dir="${TMPDIR:-/tmp}/hy2-vless-install"
    install -d -m 700 "$dir" 2>/dev/null || return 1
  fi

  HY2_LOG_DIR="$dir"
  export HY2_LOG_DIR
}

hy2_new_log_file() {
  local name="${1:-run}"

  hy2_log_dir_prepare || return 1

  name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9_.-' '_')"

  local file="${HY2_LOG_DIR}/${name}.$(date +%Y%m%d-%H%M%S).$$.log"

  : > "$file" || return 1
  chmod 600 "$file" 2>/dev/null || true

  printf '%s\n' "$file"
}

hy2_status_start() {
  _hy2_color_defaults
  printf " ${LIGHT_CYAN}▶${PLAIN} %s ... " "$*"
}

hy2_status_ok() {
  _hy2_color_defaults
  printf "%b\n" "${LIGHT_GREEN}✔ 成功${PLAIN}"
}

hy2_status_fail() {
  _hy2_color_defaults
  printf "%b\n" "${LIGHT_RED}✘ 失败${PLAIN}"
}

hy2_cmd_label() {
  local cmd="$*"

  case "$cmd" in
    *apt-get*update*|*apk\ update*|*yum*makecache*)
      echo "刷新系统软件源"
      ;;
    *apt-get*install*|*apk*add*|*yum*install*)
      echo "安装系统依赖"
      ;;
    *systemctl*daemon-reload*)
      echo "重载系统服务配置"
      ;;
    *systemctl*restart*|*rc-service*restart*)
      echo "重启系统服务"
      ;;
    *systemctl*start*|*rc-service*start*)
      echo "启动系统服务"
      ;;
    *systemctl*stop*|*rc-service*stop*)
      echo "停止系统服务"
      ;;
    *curl*|*wget*)
      echo "下载远程文件"
      ;;
    *tar*)
      echo "解压安装文件"
      ;;
    *)
      echo "执行系统命令"
      ;;
  esac
}

hy2_progress_run_shell_with_log() {
  local label="$1"
  local logfile="$2"
  local seconds="$3"
  shift 3

  local cmd="$*"
  local rc=0

  : > "$logfile" || return 1
  chmod 600 "$logfile" 2>/dev/null || true

  hy2_status_start "$label"

  if [[ -n "$seconds" && "$seconds" =~ ^[0-9]+$ ]] && command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" bash -c "$cmd" >>"$logfile" 2>&1 || rc=$?
  else
    bash -c "$cmd" >>"$logfile" 2>&1 || rc=$?
  fi

  if [[ "$rc" -eq 0 ]]; then
    hy2_status_ok
    return 0
  fi

  hy2_status_fail
  printf " ${LIGHT_YELLOW}日志已保存：%s${PLAIN}\n" "$logfile"

  if [[ "${HY2_SHOW_LOG:-0}" == "1" ]]; then
    tail -n 120 "$logfile" 2>/dev/null || true
  else
    printf " ${LIGHT_YELLOW}查看详细日志：tail -n 120 %s${PLAIN}\n" "$logfile"
    printf " ${LIGHT_YELLOW}实时调试模式：HY2_SHOW_LOG=1 bash install.sh${PLAIN}\n"
  fi

  return "$rc"
}

run_quiet_shell() {
  local label="$1"
  shift

  local seconds=""

  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    seconds="$1"
    shift
  fi

  local logfile
  logfile="$(hy2_new_log_file run)" || return 1

  hy2_progress_run_shell_with_log "$label" "$logfile" "$seconds" "$*"
}

run_quiet() {
  local label="$1"
  shift

  local logfile rc=0

  logfile="$(hy2_new_log_file run)" || return 1

  hy2_status_start "$label"

  "$@" >>"$logfile" 2>&1 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    hy2_status_ok
    return 0
  fi

  hy2_status_fail
  printf " ${LIGHT_YELLOW}日志已保存：%s${PLAIN}\n" "$logfile"

  if [[ "${HY2_SHOW_LOG:-0}" == "1" ]]; then
    tail -n 120 "$logfile" 2>/dev/null || true
  else
    printf " ${LIGHT_YELLOW}查看详细日志：tail -n 120 %s${PLAIN}\n" "$logfile"
  fi

  return "$rc"
}

jq_update_singbox_config() {
  local filter="$1"
  local config="${2:-/etc/sing-box/config.json}"
  local tmp_dir="${HY2_CONFIG_TMP_DIR:-/etc/sing-box/.tmp}"
  local tmp=""

  if [[ -L /etc/sing-box || -L "$tmp_dir" ]]; then
    red " [✘] 配置目录不能是符号链接，已拒绝写入。"
    return 1
  fi

  install -d -m 700 /etc/sing-box "$tmp_dir" 2>/dev/null || return 1
  tmp="$(mktemp "$tmp_dir/sb_patch.XXXXXX.json")" || return 1

  if jq "$filter" "$config" >"$tmp" \
    && [[ -s "$tmp" ]] \
    && jq -e empty "$tmp" >/dev/null 2>&1; then
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$config"
    return 0
  fi

  rm -f -- "$tmp" 2>/dev/null || true
  return 1
}
# HY2_QUIET_PROGRESS_V2_END
