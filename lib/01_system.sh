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
[K"
    echo -en " [1;36m▶ ${msg}...[0m "
    
    # 幽灵进程接管：将真实指令打入黑洞并在后台执行，完美规避 SSH 断流
    "$@" >/tmp/run_task.log 2>&1 &
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
        printf ""
    done
    wait $pid
    local exit_code=$?
    trap - SIGINT # 任务正常结束，解除拦截
    
    if [ $exit_code -eq 0 ]; then
        printf "[1;32m[✔] 成功！      [0m
"
    else
        printf "[1;31m[✘] 失败！(日志存至 /tmp/run_task.log)[0m
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
        echo -e "
 [1;33m▶ [内存防爆盾] 检测到极小内存 ($total_ram MB)，正动态挂载 512MB 虚拟内存防宕机...[0m"
        dd if=/dev/zero of=/tmp/hy2_swap bs=1M count=512 status=none
        chmod 600 /tmp/hy2_swap
        mkswap /tmp/hy2_swap >/dev/null 2>&1
        swapon /tmp/hy2_swap >/dev/null 2>&1
        swap_added=1
    fi

    # 清理多余空格并截断超长包名用于 UI 展示
    local display_pkgs=$(echo "$pkgs" | tr -s ' ' | cut -c 1-30)
    echo -en " [1;36m▶ 正在静默极速安装底层依赖: [0;32m${display_pkgs}...[0m "
    
    # 防卡顿：开启子进程静默重定向安装
    (
        if [ "$pkg_mgr" == "apk" ]; then
            command apk update >/tmp/pkg.log 2>&1
            command apk add --no-cache $pkgs >>/tmp/pkg.log 2>&1
        else
            export DEBIAN_FRONTEND=noninteractive
            command apt-get update -q -y >/tmp/pkg.log 2>&1
            command apt-get install -q -y $pkgs >>/tmp/pkg.log 2>&1
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
        printf ""
    done
    wait $pid
    local exit_code=$?
    trap - SIGINT # 任务正常结束，解除拦截

    # 卸载内存装甲，做到来去无痕
    if [ "$swap_added" -eq 1 ]; then
        swapoff /tmp/hy2_swap >/dev/null 2>&1
        rm -f /tmp/hy2_swap
    fi

    if [ $exit_code -eq 0 ]; then
        printf "[1;32m[✔] 成功！      [0m
"
    else
        printf "[1;31m[✘] 失败！(日志存至 /tmp/run_task.log)[0m
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
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
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



# --- V1.5.6 内核级 BDP 提速与日志自愈 (超体引擎) ---
_apply_v156_kernel_tuning() {
    # 1. 解除 Linux 内核跨洲高延迟 TCP 缓冲区锁喉 (BDP 优化)
    if ! grep -q "net.ipv4.tcp_rmem" /etc/sysctl.conf 2>/dev/null; then
        echo -e " \033[1;36m▶ 正在进行内核级 TCP 缓冲区深度扩容 (BDP 跨洲网络提速)...\033[0m "
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
_apply_v156_kernel_tuning


# --- V1.5.7 环境驯化与全局劫持引擎 ---
_clean_zombie_ports() {
    for port in 443 8443; do
        if command -v fuser >/dev/null 2>&1; then
            fuser -k -9 ${port}/tcp >/dev/null 2>&1 || true
            fuser -k -9 ${port}/udp >/dev/null 2>&1 || true
        elif command -v lsof >/dev/null 2>&1; then
            lsof -ti:${port} | xargs -r kill -9 >/dev/null 2>&1 || true
        fi
    done
}

_punch_firewalls() {
    if command -v ufw >/dev/null 2>&1; then ufw disable >/dev/null 2>&1 || true; fi
    if command -v firewall-cmd >/dev/null 2>&1; then systemctl stop firewalld >/dev/null 2>&1 || true; systemctl disable firewalld >/dev/null 2>&1 || true; fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -P INPUT ACCEPT >/dev/null 2>&1 || true
        iptables -P FORWARD ACCEPT >/dev/null 2>&1 || true
        iptables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
        iptables -F >/dev/null 2>&1 || true
        iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited >/dev/null 2>&1 || true
        iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited >/dev/null 2>&1 || true
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -P INPUT ACCEPT >/dev/null 2>&1 || true
        ip6tables -P FORWARD ACCEPT >/dev/null 2>&1 || true
        ip6tables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
        ip6tables -F >/dev/null 2>&1 || true
    fi
}

_env_prepare() {
    _clean_zombie_ports
    _punch_firewalls
}

# 【黑科技】Bash 命令劫持 (Command Hook)
# 直接接管当前运行环境下的系统级进程管理命令
systemctl() {
    local args="$*"
    if [[ "$args" == *"sing-box"* ]] && [[ "$args" == *"start"* || "$args" == *"restart"* || "$args" == *"enable"* ]]; then
        if [ -z "$_HOOK_ENV_DONE" ]; then
            export _HOOK_ENV_DONE=1
            _env_prepare
        fi
    fi
    command systemctl "$@"
}

rc-service() {
    local args="$*"
    if [[ "$args" == *"sing-box"* ]] && [[ "$args" == *"start"* || "$args" == *"restart"* ]]; then
        if [ -z "$_HOOK_ENV_DONE" ]; then
            export _HOOK_ENV_DONE=1
            _env_prepare
        fi
    fi
    command rc-service "$@"
}


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
