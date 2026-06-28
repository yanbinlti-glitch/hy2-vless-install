#!/usr/bin/env bash


# --- V1.5.1 纯 IPv6 双栈自适应探针 ---
get_link_ip() {
    local ip="${PUBLIC_IP}"
    if [[ -z "$ip" || "$ip" == "未检测到"* || "$ip" == "未知"* || "$ip" == "127.0.0.1" ]]; then
        local my_ipv6=$(cat /tmp/hy2_ipv6*.tmp 2>/dev/null | head -n 1)
        [[ -z "$my_ipv6" ]] && my_ipv6=$(curl -fsS6m2 https://api64.ipify.org 2>/dev/null || ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2}' | cut -d/ -f1 | head -n 1)
        if [[ -n "$my_ipv6" && "$my_ipv6" != "未检测到"* ]]; then
            ip="[${my_ipv6}]"
        else
            ip="127.0.0.1"
        fi
    fi
    echo "$ip"
}

get_sub_ip() {
    local ip="${PUBLIC_IP}"
    if [[ -z "$ip" || "$ip" == "未检测到"* || "$ip" == "未知"* || "$ip" == "127.0.0.1" ]]; then
        local my_ipv6=$(cat /tmp/hy2_ipv6*.tmp 2>/dev/null | head -n 1)
        [[ -z "$my_ipv6" ]] && my_ipv6=$(curl -fsS6m2 https://api64.ipify.org 2>/dev/null || ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2}' | cut -d/ -f1 | head -n 1)
        [[ -n "$my_ipv6" && "$my_ipv6" != "未检测到"* ]] && ip="$my_ipv6"
    fi
    echo "$ip"
}



# --- V1.4.9 全链路通用静默 UI 引擎 ---
_smart_run() {
    local msg="$1"
    shift
    # 清理当前行终端残留
    printf "
[K"
    printf "%b" " [1;36m▶ ${msg}...[0m "
    
    # 幽灵进程接管：将真实指令打入黑洞并在后台执行，完美规避 SSH 断流
    "$@" >"$HY2_VLESS_RUN_LOG" 2>&1 &
    local pid=$!
    
    # 内核级中断拦截 (Trap)：防止用户 Ctrl+C 导致后台任务变成僵尸进程锁死系统
    trap 'kill -9 $pid 2>/dev/null; printf "\n\b\b\b\033[1;31m[!] 检测到强行中断 (Ctrl+C)，已物理连坐击杀后台僵尸进程！\033[0m\n"; trap - SIGINT; return 1' SIGINT
    
    # UI 线程自旋锁
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.15
        printf ""
    done
    wait $pid
    local exit_code=$?
    trap - SIGINT # 任务正常结束，解除拦截
    
    if [ $exit_code -eq 0 ]; then
        printf "[1;32m[✔] 成功！      [0m
"
    else
        printf "[1;31m[✘] 失败！(日志存至 $HY2_VLESS_RUN_LOG)[0m
"
    fi
    return $exit_code
}



# --- V1.4.8 OOM防爆盾与静默安装引擎 ---
_smart_install() {
    local pkg_mgr="$1"
    shift
    local pkgs="$*"
    
    local total_ram=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local swap_added=0
    
    # 低配防死机：动态挂载 512MB 虚拟内存
    if [[ -n "$total_ram" ]] && [ "$total_ram" -lt 400 ] && [ "$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')" -eq 0 ]; then
        printf "%b
" "
 [1;33m▶ [内存防爆盾] 检测到极小内存 ($total_ram MB)，正动态挂载 512MB 虚拟内存防宕机...[0m"
        rm -f "$HY2_VLESS_SWAP_FILE"
        dd if=/dev/zero of="$HY2_VLESS_SWAP_FILE" bs=1M count=512 status=none
        chmod 644 "$HY2_VLESS_SWAP_FILE"
        mkswap "$HY2_VLESS_SWAP_FILE" >/dev/null 2>&1
        swapon "$HY2_VLESS_SWAP_FILE" >/dev/null 2>&1
        swap_added=1
    fi

    # 清理多余空格并截断超长包名用于 UI 展示
    local display_pkgs=$(echo "$pkgs" | tr -s ' ' | cut -c 1-30)
    printf "%b" " [1;36m▶ 正在静默极速安装底层依赖: [0;32m${display_pkgs}...[0m "
    
    # 防卡顿：开启子进程静默重定向安装
    (
        if [ "$pkg_mgr" == "apk" ]; then
            command apk update >"$HY2_VLESS_PKG_LOG" 2>&1
            command apk add --no-cache $pkgs >>"$HY2_VLESS_PKG_LOG" 2>&1
        else
            export DEBIAN_FRONTEND=noninteractive
            command apt-get update -q -y >"$HY2_VLESS_PKG_LOG" 2>&1
            command apt-get install -q -y $pkgs >>"$HY2_VLESS_PKG_LOG" 2>&1
        fi
    ) &
    local pid=$!
    
    # 防假死：UI 线程动画自旋锁
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.15
        printf ""
    done
    wait $pid
    local exit_code=$?
    trap - SIGINT # 任务正常结束，解除拦截

    # 卸载内存装甲，做到来去无痕
    if [ "$swap_added" -eq 1 ]; then
        swapoff "$HY2_VLESS_SWAP_FILE" >/dev/null 2>&1
        rm -f "$HY2_VLESS_SWAP_FILE"
    fi

    if [ $exit_code -eq 0 ]; then
        printf "[1;32m[✔] 成功！      [0m
"
    else
        printf "[1;31m[✘] 失败！(日志存至 $HY2_VLESS_PKG_LOG)[0m
"
    fi
}

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
#  2. 基础系统判定与快捷命令覆写
# =================================================================
[[ $EUID -ne 0 ]] && red " [错误] 请在 root 用户下运行此脚本！" && exit 1

# --- 安全运行目录与日志文件 ---
# 不在公共 /tmp 中创建固定名称的日志或交换文件。
readonly HY2_VLESS_STATE_DIR="/var/lib/hy2-vless-install"
readonly HY2_VLESS_LOG_DIR="/var/log/hy2-vless-install"
readonly HY2_VLESS_RUN_LOG="$HY2_VLESS_LOG_DIR/run_task.log"
readonly HY2_VLESS_PKG_LOG="$HY2_VLESS_LOG_DIR/pkg.log"
readonly HY2_VLESS_SWAP_FILE="$HY2_VLESS_STATE_DIR/install.swap"

_prepare_secure_runtime_paths() {
  local dir
  local file

  for dir in \
    "$HY2_VLESS_STATE_DIR" \
    "$HY2_VLESS_LOG_DIR"
  do
    if [[ -L "$dir" ]]; then
      red " [错误] 安全目录不能是符号链接：$dir"
      return 1
    fi

    mkdir -p "$dir" || return 1
    chmod 700 "$dir" || return 1
  done

  for file in \
    "$HY2_VLESS_RUN_LOG" \
    "$HY2_VLESS_PKG_LOG"
  do
    if [[ -L "$file" ]]; then
      red " [错误] 日志文件不能是符号链接：$file"
      return 1
    fi

    touch "$file" || return 1
    chmod 644 "$file" || return 1
  done
}

_prepare_secure_runtime_paths || exit 1

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
        PKG_INSTALL="apk add --no-cache"
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
    centos|rhel|almalinux|rocky|ol|amzn)
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
  local ip="${1-}"
  local lower=""
  local octet=""
  local value=0
  local a=0
  local b=0
  local c=0
  local d=0

  [[ -n "$ip" ]] || return 1

  # Python 标准库可以完整处理压缩 IPv6、IPv4 边界值
  # 以及私网、回环、组播和保留地址。
  if command -v python3 >/dev/null 2>&1; then
    python3 \
      -c '
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)

raise SystemExit(0 if address.is_global else 1)
' \
      "$ip" \
      >/dev/null 2>&1

    return $?
  fi

  # Python 缺失时使用严格 IPv4 后备检查。
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r a b c d <<< "$ip"

    for octet in "$a" "$b" "$c" "$d"; do
      [[ "$octet" =~ ^[0-9]+$ ]] ||
        return 1

      value=$((10#$octet))

      (( value >= 0 && value <= 255 )) ||
        return 1
    done

    a=$((10#$a))
    b=$((10#$b))

    # 拒绝非公网 IPv4 范围。
    (( a != 0 )) || return 1
    (( a != 10 )) || return 1
    (( a != 127 )) || return 1
    (( a < 224 )) || return 1

    if (( a == 100 && b >= 64 && b <= 127 )); then
      return 1
    fi

    if (( a == 169 && b == 254 )); then
      return 1
    fi

    if (( a == 172 && b >= 16 && b <= 31 )); then
      return 1
    fi

    if (( a == 192 && b == 168 )); then
      return 1
    fi

    return 0
  fi

  # IPv6 后备路径只接受十六进制和冒号，
  # 再交给 iproute2 做语法解析。
  [[ "$ip" == *:* ]] || return 1
  [[ "$ip" != *[!0-9A-Fa-f:]* ]] || return 1
  command -v ip >/dev/null 2>&1 || return 1
  ip -6 route get "$ip" >/dev/null 2>&1 || return 1

  lower="${ip,,}"

  case "$lower" in
    "::"|"::1"|fe8*|fe9*|fea*|feb*|fc*|fd*|ff*)
      return 1
      ;;
  esac

  return 0
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
            ip=$(curl -fsS4m4 "$ep" 2>/dev/null | head -n1 | tr -d '[:space:]')
            if valid_ip_literal "$ip"; then break; fi
            ip=""
        done
    fi
    if [[ -z "$ip" ]]; then
        for ep in "${endpoints6[@]}"; do
            ip=$(curl -fsS6m4 "$ep" 2>/dev/null | head -n1 | tr -d '[:space:]')
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



# --- V1.5.6 内核级 BDP 提速与日志自愈 (超体引擎) ---
_apply_v156_kernel_tuning() {
    # 1. 解除 Linux 内核跨洲高延迟 TCP 缓冲区锁喉 (BDP 优化)
    if ! grep -q "net.ipv4.tcp_rmem" /etc/sysctl.conf 2>/dev/null; then
        printf "%b
" " \033[1;36m▶ 正在进行内核级 TCP 缓冲区深度扩容 (BDP 跨洲网络提速)...\033[0m "
        cat << 'SYSCTL_EOF' >> /etc/sysctl.conf

# V1.5.6 Sing-box BDP Cross-Continent TCP Tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
net.core.rmem_max = 536870912
net.core.wmem_max = 536870912
net.ipv4.tcp_fastopen = 3
SYSCTL_EOF
        sysctl -p >/dev/null 2>&1
    fi

    # 2. 挂载日志核爆防御看门狗 (每天凌晨 3 点静默清空日志，防廉价 VPS 爆盘死机)
    (crontab -l 2>/dev/null | grep -v "sing-box_log_gc"; echo "0 3 * * * truncate -s 0 /var/log/sing-box/*.log >/dev/null 2>&1 # sing-box_log_gc") | crontab -
}

# 脚本启动时自动执行环境体检与修复
if [[ "${HY2_VLESS_ENABLE_KERNEL_TUNING:-0}" == "1" ]]; then
  yellow " [提示] 已显式启用全局内核与定时任务调优。"

  _apply_v156_kernel_tuning
else
  yellow " [安全] 默认不修改全局 sysctl 或 root 定时任务。"
fi


# --- V1.5.7 安全修复：取消全局服务和防火墙命令劫持 ---
#
# 不再覆盖 systemctl / rc-service。
# 不再自动关闭 UFW 或 firewalld。
# 不再清空 iptables / ip6tables。
# 不再强制杀死占用 443 或 8443 端口的进程。
#
# 服务控制由 lib/02_service_firewall.sh 中的 svc_* 函数负责；
# 端口冲突应由安装流程检测并提示用户选择其他端口。

# --- V1.5.9 全字符安全编码引擎 ---
# 纯 Bash 原生实现的 RFC 3986 标准 URI 编码器，完美清洗特殊符号与中文字符
_url_encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) o="${c}" ;;
            *) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}
