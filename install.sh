#!/bin/bash

export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

# =================================================================
#  1. 现代化极简 UI 色彩库 & 全局中断防崩溃保护
# =================================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PURPLE="\033[35m"

LIGHT_RED="\033[1;31m"
LIGHT_GREEN="\033[1;32m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_PURPLE="\033[1;35m"
PLAIN="\033[0m"

red()    { echo -e "${LIGHT_RED}$1${PLAIN}"; }
green()  { echo -e "${LIGHT_GREEN}$1${PLAIN}"; }
yellow() { echo -e "${LIGHT_YELLOW}$1${PLAIN}"; }
purple() { echo -e "${LIGHT_PURPLE}$1${PLAIN}"; }

print_line() {
    green " ──────────────────────────────────────────────────────────"
}

trap 'echo -e "\n\n ${LIGHT_RED}[警告] 检测到强行中断，脚本已安全退出。${PLAIN}"; exit 1' INT TERM

# =================================================================
#  2. 基础系统判定与快捷命令覆写 (666)
# =================================================================
[[ $EUID -ne 0 ]] && red " [错误] 请在 root 用户下运行此脚本！" && exit 1

SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")
if [[ -f "$SCRIPT_PATH" && "$(head -n 1 "$SCRIPT_PATH" 2>/dev/null)" == "#!/bin/bash" ]]; then
    if [[ "$SCRIPT_PATH" != "/usr/bin/666" ]]; then
        cp -f "$SCRIPT_PATH" /usr/bin/666
        chmod +x /usr/bin/666
    fi
    [[ -f "/usr/bin/hy2" ]] && rm -f "/usr/bin/hy2"
fi

REGEX=("alpine" "debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "amazon linux" "fedora")
RELEASE=("Alpine" "Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apk update" "apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apk add" "apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        PKG_UPDATE="${PACKAGE_UPDATE[int]}"
        PKG_INSTALL="${PACKAGE_INSTALL[int]}"
        [[ -n $SYSTEM ]] && break
    fi
done
[[ -z $SYSTEM ]] && red " [错误] 目前暂不支持您的 VPS 操作系统！" && exit 1

PUBLIC_IP=""
realip() {
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != *.* && "$PUBLIC_IP" != *:* ]]; then
        return
    fi
    local ip=""
    if ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
        ip=$(curl -s4m3 api.ipify.org -k || curl -s4m3 ifconfig.me -k || curl -s4m3 ip.sb -k)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6m3 api64.ipify.org -k || curl -s6m3 ifconfig.me -k || curl -s6m3 ip.sb -k)
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

# =================================================================
#  3. 服务管理与标签化防火墙管控 (精准卸载支持)
# =================================================================
svc_start()   { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" start; else systemctl start "$1"; fi; }
svc_stop()    { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" stop; else systemctl stop "$1"; fi; }
svc_enable()  { if [[ $SYSTEM == "Alpine" ]]; then rc-update add "$1" default; else systemctl enable "$1"; fi; }
svc_disable() { if [[ $SYSTEM == "Alpine" ]]; then rc-update del "$1" default; else systemctl disable "$1"; fi; }

is_svc_active() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service "$1" status 2>/dev/null | grep -q 'started'
    else
        systemctl is-active --quiet "$1" 2>/dev/null
    fi
}

save_iptables() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service iptables save >/dev/null 2>&1
        rc-service ip6tables save >/dev/null 2>&1
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
        service iptables save >/dev/null 2>&1
        service ip6tables save >/dev/null 2>&1
    else
        if command -v netfilter-persistent >/dev/null; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

open_port() {
    local port=$1
    local proto=$2
    local tag=$3
    mkdir -p /etc/sing-box
    echo "$tag:$proto:$port" >> /etc/sing-box/.firewall_state
    
    if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --zone=public --add-port=$port/$proto --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $port/$proto >/dev/null 2>&1
    else
        iptables -I INPUT -p $proto --dport $port -j ACCEPT >/dev/null 2>&1
        ip6tables -I INPUT -p $proto --dport $port -j ACCEPT >/dev/null 2>&1
        save_iptables
    fi
}

close_port_by_tag() {
    local target_tag=$1
    if [[ -f /etc/sing-box/.firewall_state ]]; then
        local tmp_state=$(mktemp)
        while IFS=: read -r tag proto port; do
            if [[ "$tag" == "$target_tag" ]]; then
                iptables-save | grep -v -- "-p $proto -m $proto --dport $port -j ACCEPT" | iptables-restore 2>/dev/null
                ip6tables-save | grep -v -- "-p $proto -m $proto --dport $port -j ACCEPT" | ip6tables-restore 2>/dev/null
                if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
                    firewall-cmd --zone=public --remove-port=$port/$proto --permanent >/dev/null 2>&1
                    firewall-cmd --reload >/dev/null 2>&1
                fi
                if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
                    ufw delete allow $port/$proto >/dev/null 2>&1
                fi
            else
                echo "$tag:$proto:$port" >> "$tmp_state"
            fi
        done < /etc/sing-box/.firewall_state
        mv "$tmp_state" /etc/sing-box/.firewall_state
    fi
    save_iptables
}

# =================================================================
#  4. 依赖环境检查与节点探测
# =================================================================
check_env() {
    clear
    echo ""
    print_line
    green "                    系统依赖与环境检查                      "
    print_line
    echo ""
    green "  当前操作系统: $SYSTEM"
    
    yellow "  正在校准系统时钟 (防御 TLS 时钟偏移瘫痪)..."
    local date_str=$(curl -sI -m 3 https://google.com 2>/dev/null | grep -i Date | cut -d' ' -f3-6)
    [[ -z "$date_str" ]] && date_str=$(curl -sI -m 3 https://cloudflare.com 2>/dev/null | grep -i Date | cut -d' ' -f3-6)
    [[ -n "$date_str" ]] && date -s "${date_str}Z" 2>/dev/null || true
    
    local cmds=("curl" "wget" "sudo" "ss" "iptables" "python3" "openssl" "socat" "qrencode" "jq" "tar" "nginx")
    local missing=0

    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" > /dev/null; then missing=1; fi
    done

    if [[ $missing -eq 1 ]]; then
        yellow "  发现缺失前置组件，正在为您自动拉取安装，请稍候..."
        [[ ! $SYSTEM == "CentOS" ]] && { $PKG_UPDATE >/dev/null 2>&1 || true; }
        
        if [[ $SYSTEM == "Alpine" ]]; then
            $PKG_INSTALL curl wget sudo procps iptables ip6tables iproute2 python3 openssl socat libqrencode-tools jq coreutils nginx tar >/dev/null 2>&1 || { red " [错误] 依赖安装失败！"; exit 1; }
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
            $PKG_INSTALL epel-release >/dev/null 2>&1 || true
            $PKG_INSTALL curl wget sudo procps iptables iptables-services iproute python3 openssl socat qrencode jq coreutils nginx tar >/dev/null 2>&1 || { red " [错误] 依赖安装失败！"; exit 1; }
        else
            export DEBIAN_FRONTEND=noninteractive
            apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y install curl wget sudo procps iptables-persistent netfilter-persistent iproute2 python3 openssl socat qrencode jq coreutils nginx tar >/dev/null 2>&1 || { red " [错误] 依赖安装失败！"; exit 1; }
        fi
        green "  所有前置依赖补全完成！"
    else
        green "  所有前置依赖检查通过，环境完美！"
    fi
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

# =================================================================
#  5. 安装交互核心流程 (双协议无缝共存与底层隔离)
# =================================================================
inst_cert() {
    yellow "  系统已统一采用安全自签模式，开始静默生成伪装 ECC 密钥对..."
    mkdir -p /etc/sing-box
    cert_path="/etc/sing-box/cert.crt"
    key_path="/etc/sing-box/private.key"
    local cert_sni="www.bing.com"
    
    openssl ecparam -genkey -name prime256v1 -out "$key_path" >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key "$key_path" -out "$cert_path" -subj "/CN=$cert_sni" >/dev/null 2>&1
    
    chmod 644 "$cert_path"
    chmod 644 "$key_path"
    echo "$cert_sni" > /etc/sing-box/cert_sni.txt
    green "  自签证书生成并降权授权成功！"
}

inst_sub_port(){
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 设置 Nginx 聚合订阅服务端口 [1024-65535] (回车随机): ${PLAIN}"
    read sub_port_input || exit 1
    [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    
    while [[ ! "$sub_port_input" =~ ^[0-9]+$ ]] || [[ "$sub_port_input" -lt 1024 ]] || [[ "$sub_port_input" -gt 65535 ]]; do
        red " [警告] 端口无效！重新设置: "
        read sub_port_input || exit 1
        [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    done
    
    while ss -tnl | grep -E -q "(:|^)$sub_port_input( |$)"; do
        red " [警告] 端口 $sub_port_input 已被占用！重新设置: "
        read sub_port_input || exit 1
        [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    done
    green " 订阅 HTTPS 端口已设置为: $sub_port_input"
    open_port $sub_port_input "tcp" "sub"
    echo "$sub_port_input" > /etc/sing-box/sub_port.txt
}

inst_singbox_core() {
    yellow "  正在拉取 Sing-box 最新版二进制核心..."
    local arch=$(uname -m)
    local sb_arch="amd64"
    [[ "$arch" == "aarch64" ]] && sb_arch="arm64"
    [[ "$arch" == "s390x" ]] && sb_arch="s390x"

    local tag_json=$(curl -s -m 10 "https://api.github.com/repos/SagerNet/sing-box/releases/latest")
    local sb_version=$(echo "$tag_json" | jq -r '.tag_name' 2>/dev/null)
    [[ -z "$sb_version" || "$sb_version" == "null" ]] && sb_version="v1.9.3"
    
    local dl_url="https://github.com/SagerNet/sing-box/releases/download/${sb_version}/sing-box-${sb_version#v}-linux-${sb_arch}.tar.gz"
    
    rm -rf /tmp/sing-box*
    wget --timeout=15 --tries=3 -qO /tmp/sing-box.tar.gz "$dl_url" || wget --timeout=15 --tries=3 -qO /tmp/sing-box.tar.gz "https://ghfast.top/$dl_url"
    
    if [[ ! -s /tmp/sing-box.tar.gz ]]; then
        red " [致命错误] Sing-box 核心下载失败！"
        exit 1
    fi
    
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    local extract_dir=$(find /tmp/ -type d -name "sing-box-*-linux-${sb_arch}")
    
    if [[ -n "$extract_dir" && -f "$extract_dir/sing-box" ]]; then
        mv -f "$extract_dir/sing-box" /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        green "  [✔] Sing-box ($sb_version) 核心就绪！"
    else
        red " [致命错误] Sing-box 核心解压或定位失败！"; exit 1
    fi
    rm -rf /tmp/sing-box*

    if [[ $SYSTEM == "Alpine" ]]; then
        cat << 'EOF' > /etc/init.d/sing-box
#!/sbin/openrc-run
description="Sing-box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background=true
pidfile="/run/sing-box.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"
rc_ulimit="-n 524288"
EOF
        chmod +x /etc/init.d/sing-box
    else
        cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sing-box
LimitNOFILE=524288
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogLevel=warning
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
}

build_base_json() {
    cat << EOF > /etc/sing-box/config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": { "servers": [ { "tag": "google", "address": "8.8.8.8", "detour": "direct" } ] },
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      {
        "ip_cidr": [ "169.254.0.0/16", "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7", "fe80::/10" ],
        "outbound": "block"
      }
    ]
  }
}
EOF
}

inst_hysteria2() {
    local is_first=1
    [[ -f /etc/sing-box/config.json ]] && is_first=0

    if [[ $is_first -eq 1 ]]; then
        inst_singbox_core
        inst_cert
        inst_sub_port
        build_base_json
    fi
    
    echo ""
    print_line
    yellow "  Hysteria 2 主端口与网络配置"
    echo -en " ${LIGHT_YELLOW} ▶ 设置 Hysteria 2 主端口 (UDP) [10000-65535] (回车随机): ${PLAIN}"
    read port || port=$(shuf -i 10000-65535 -n 1)
    [[ -z $port ]] && port=$(shuf -i 10000-65535 -n 1)
    
    while ss -unl | grep -E -q "(:|^)$port( |$)"; do
        red " [警告] 端口 $port 已被占用！"
        read port || exit 1
        [[ -z $port ]] && port=$(shuf -i 10000-65535 -n 1)
    done
    green " 节点主端口已设置为: $port (UDP)"
    open_port $port "udp" "hy2-in"
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 设置节点连接密码 (回车自动生成): ${PLAIN}"
    read auth_pwd || exit 1
    [[ -z $auth_pwd ]] && auth_pwd=$(gen_random_str 16)
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 Hy2_Node]: ${PLAIN}"
    read custom_node_name || exit 1
    [[ -z $custom_node_name ]] && custom_node_name="Hy2_Node"
    echo "$custom_node_name" > /etc/sing-box/hy2_name.txt
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 是否开启防阻断 Salamander 混淆？(y/n) [默认: y]: ${PLAIN}"
    read enable_obfs || exit 1
    [[ -z $enable_obfs ]] && enable_obfs="y"
    local obfs_pwd=""
    if [[ "$enable_obfs" == "y" || "$enable_obfs" == "Y" ]]; then
        obfs_pwd=$(gen_random_str 12)
        green " 已开启混淆，密钥为: $obfs_pwd"
    fi
    
    # 结构化 Append JSON 防御
    jq --arg p "$port" --arg pwd "$auth_pwd" --arg cp "/etc/sing-box/cert.crt" --arg kp "/etc/sing-box/private.key" '
    .inbounds += [{
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ($p | tonumber),
      "users": [{"password": $pwd}],
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cp, "key_path": $kp }
    }]' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    
    if [[ -n "$obfs_pwd" ]]; then
        jq --arg obfs "$obfs_pwd" '( .inbounds[] | select(.tag=="hy2-in") ) += { "obfs": {"type": "salamander", "password": $obfs} }' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    fi
    
    chmod 600 /etc/sing-box/config.json
    svc_enable sing-box
    svc_start sing-box
    generate_client_configs
    
    echo ""
    green "  [✔] Hysteria 2 服务端已追加部署成功！"
    sleep 2
}

inst_vless_reality() {
    local is_first=1
    [[ -f /etc/sing-box/config.json ]] && is_first=0

    if [[ $is_first -eq 1 ]]; then
        inst_singbox_core
        inst_cert
        inst_sub_port
        build_base_json
    fi
    
    echo ""
    print_line
    yellow "  VLESS + Reality 端口与特征配置"
    echo -en " ${LIGHT_YELLOW} ▶ 请设置主端口 (TCP) [1-65535] (强烈推荐 443，回车默认 443): ${PLAIN}"
    read port || port=443
    [[ -z $port ]] && port=443
    
    if ss -tnl | grep -E -q "(:|^)$port( |$)"; then
        red " [高危阻断] TCP 端口 $port 已被占用！(请检查 Nginx 或其他 Web 进程)"
        exit 1
    fi
    green " 节点主端口已设置为: $port (TCP)"
    open_port $port "tcp" "vless-in"
    
    echo ""
    yellow "  正在通过 Sing-box 核心生成原生 x25519 密钥对与 Short ID..."
    local keypair_json=$(/usr/local/bin/sing-box generate reality-keypair)
    local v_private_key=$(echo "$keypair_json" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    local v_public_key=$(echo "$keypair_json" | awk '/PublicKey/ {print $2}' | tr -d '"')
    local v_short_id=$(/usr/local/bin/sing-box generate rand --hex 8)
    local v_uuid=$(/usr/local/bin/sing-box generate uuid)
    
    echo "$v_public_key" > /etc/sing-box/reality_pub.txt
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 Vless_Reality_Node]: ${PLAIN}"
    read custom_node_name || exit 1
    [[ -z $custom_node_name ]] && custom_node_name="Vless_Reality_Node"
    echo "$custom_node_name" > /etc/sing-box/vless_name.txt
    
    # 结构化 Append JSON 防御
    jq --arg p "$port" --arg uuid "$v_uuid" --arg priv "$v_private_key" --arg sid "$v_short_id" '
    .inbounds += [{
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ($p | tonumber),
      "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.microsoft.com", "server_port": 443 },
          "private_key": $priv,
          "short_id": [$sid]
        }
      }
    }]' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    
    chmod 600 /etc/sing-box/config.json
    svc_enable sing-box
    svc_start sing-box
    generate_client_configs
    
    echo ""
    green "  [✔] VLESS + Reality 服务端已追加部署成功！"
    sleep 2
}

inst_singbox() {
    check_env
    check_installed_nodes
    
    if [[ $has_hy2 -eq 1 && $has_vless -eq 1 ]]; then
        echo ""
        red "  [阻断] 您已成功部署了双节点 (Hysteria 2 + VLESS)，无需重复安装！"
        sleep 2; return
    fi
    
    if [[ $has_hy2 -eq 1 ]]; then
        yellow "  检测到您已安装 Hysteria 2，正在为您直接拉起 VLESS 补充安装流程..."
        sleep 2; inst_vless_reality; return
    elif [[ $has_vless -eq 1 ]]; then
        yellow "  检测到您已安装 VLESS，正在为您直接拉起 Hysteria 2 补充安装流程..."
        sleep 2; inst_hysteria2; return
    fi
    
    clear
    echo ""
    green " ──────────────────────────────────────────────────────────"
    green "                 底层代理协议选择配置                      "
    green " ──────────────────────────────────────────────────────────"
    echo ""
    yellow "  Sing-box 核心支持多协议矩阵，您可以先选装一个，后续可再次进入菜单补齐："
    echo ""
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}Hysteria 2 (基于 UDP/QUIC，极速抗丢包，默认推荐)${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_PURPLE}VLESS + Reality (基于 TCP/XTLS，指纹级伪装，抗封锁推荐)${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [1-2] (默认1): ${PLAIN}"
    read protoInput || protoInput=1
    [[ -z "$protoInput" ]] && protoInput=1

    if [[ "$protoInput" == "2" ]]; then
        inst_vless_reality
    else
        inst_hysteria2
    fi
}

# =================================================================
#  6. 核心业务处理与多态聚合订阅引擎 (HTTPS 强加密)
# =================================================================
generate_client_configs() {
    realip
    check_installed_nodes
    
    if [[ $has_hy2 -eq 0 && $has_vless -eq 0 ]]; then
        rm -f /etc/nginx/conf.d/sing-box-sub.conf /etc/nginx/sites-enabled/sing-box-sub.conf /etc/nginx/sites-available/sing-box-sub.conf /etc/nginx/http.d/sing-box-sub.conf
        if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx reload >/dev/null 2>&1; else systemctl reload nginx >/dev/null 2>&1; fi
        return
    fi

    local sub_port=$(cat /etc/sing-box/sub_port.txt 2>/dev/null)
    local sub_uuid=$(cat /root/.hy2_sub_uuid 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9')
    [[ -z "$sub_uuid" ]] && sub_uuid=$(echo "${PUBLIC_IP}-Singbox-Sub" | md5sum | head -c 16)
    echo "$sub_uuid" > /root/.hy2_sub_uuid
    echo "$sub_uuid" > /etc/sing-box/sub_path.txt
    
    local web_dir="/var/www/sing-box"
    mkdir -p "$web_dir/$sub_uuid"
    
    local url_all=""
    local proxy_yaml=""
    local proxy_names=""
    local yaml_json_ip="$PUBLIC_IP"
    local uri_ip="$PUBLIC_IP"
    [[ "$PUBLIC_IP" == *":"* ]] && uri_ip="[$PUBLIC_IP]"

    # 聚合: Hysteria 2
    if [[ $has_hy2 -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/hy2_name.txt 2>/dev/null || echo "Hy2_Node")
        local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
        local bind_port=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' /etc/sing-box/config.json)
        local pwd=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' /etc/sing-box/config.json)
        local sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.bing.com")
        local obfs=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .obfs.password // empty' /etc/sing-box/config.json)

        local s_pwd=$(PWD="$pwd" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('PWD', '')))")
        local url="hy2://$s_pwd@$uri_ip:$bind_port/?insecure=1&sni=$sni"
        [[ -n "$obfs" ]] && url="${url}&obfs=salamander&obfs-password=${obfs}"
        url="${url}#${safe_node_name}"
        url_all="${url_all}${url}\n"

        proxy_yaml="${proxy_yaml}
  - name: '${node_name}'
    type: hysteria2
    server: \"$yaml_json_ip\"
    port: $bind_port
    password: '${pwd}'
    sni: \"$sni\"
    skip-cert-verify: true
    alpn:
      - h3"
        [[ -n "$obfs" ]] && proxy_yaml="${proxy_yaml}
    obfs: salamander
    obfs-password: \"$obfs\""
        proxy_names="${proxy_names}\n      - '${node_name}'"
    fi

    # 聚合: VLESS
    if [[ $has_vless -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/vless_name.txt 2>/dev/null || echo "Vless_Node")
        local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
        local bind_port=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .listen_port' /etc/sing-box/config.json)
        local uuid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .users[0].uuid' /etc/sing-box/config.json)
        local sni="www.microsoft.com"
        local pub=$(cat /etc/sing-box/reality_pub.txt 2>/dev/null)
        local sid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.reality.short_id[0]' /etc/sing-box/config.json)

        local url="vless://$uuid@$uri_ip:$bind_port/?security=reality&encryption=none&pbk=$pub&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$sni&sid=$sid#${safe_node_name}"
        url_all="${url_all}${url}\n"

        proxy_yaml="${proxy_yaml}
  - name: '${node_name}'
    type: vless
    server: \"$yaml_json_ip\"
    port: $bind_port
    uuid: $uuid
    network: tcp
    tls: true
    udp: true
    xudp: true
    flow: xtls-rprx-vision
    servername: $sni
    client-fingerprint: chrome
    reality-opts:
      public-key: $pub
      short-id: $sid"
        proxy_names="${proxy_names}\n      - '${node_name}'"
    fi

    echo -e "$url_all" > "$web_dir/$sub_uuid/url.txt"
    echo -e "$url_all" | base64 -w 0 2>/dev/null > "$web_dir/$sub_uuid/sub_b64.txt" || echo -e "$url_all" | base64 | tr -d '\r\n' > "$web_dir/$sub_uuid/sub_b64.txt"
    
    cat << EOF > "$web_dir/$sub_uuid/clash-meta-sub.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: true

proxies:$proxy_yaml

proxy-groups:
  - name: "节点选择"
    type: select
    proxies:$proxy_names
      - DIRECT

rules:
$([[ "$yaml_json_ip" == *":"* ]] && echo "  - IP-CIDR6,$yaml_json_ip/128,DIRECT,no-resolve" || echo "  - IP-CIDR,$yaml_json_ip/32,DIRECT,no-resolve")
  - DST-PORT,$sub_port,DIRECT
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
EOF

    chmod -R 755 "$web_dir"

    local nginx_conf_file="/etc/nginx/conf.d/sing-box-sub.conf"
    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
        nginx_conf_file="/etc/nginx/sites-available/sing-box-sub.conf"
    elif [[ $SYSTEM == "Alpine" ]]; then
        mkdir -p /etc/nginx/http.d
        nginx_conf_file="/etc/nginx/http.d/sing-box-sub.conf"
    else
        mkdir -p /etc/nginx/conf.d
    fi
    
    local listen_ipv6=""
    [[ -f /proc/net/if_inet6 ]] && listen_ipv6="listen [::]:$sub_port ssl;"

    # 强制 TLS 加密防嗅探
    cat << EOF > "$nginx_conf_file"
server {
    listen $sub_port ssl;
    $listen_ipv6
    
    ssl_certificate /etc/sing-box/cert.crt;
    ssl_certificate_key /etc/sing-box/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    root $web_dir;

    location = /$sub_uuid {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
        if (\$http_user_agent ~* "(clash|meta|verge|stash|mihomo)") { rewrite ^ /$sub_uuid/clash-meta-sub.yaml last; }
        rewrite ^ /$sub_uuid/sub_b64.txt last;
    }

    location ~ ^/$sub_uuid/(clash-meta-sub\.yaml|sub_b64\.txt)$ {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
    }

    location / { return 403; }
}
EOF

    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        ln -sf /etc/nginx/sites-available/sing-box-sub.conf /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi

    if nginx -t >/dev/null 2>&1; then
        svc_enable nginx
        if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx restart >/dev/null 2>&1; else systemctl restart nginx >/dev/null 2>&1; fi
    fi
}

clean_env() {
    local mode="$1"
    close_port_by_tag "hy2-in"
    close_port_by_tag "vless-in"
    close_port_by_tag "sub"

    svc_stop sing-box >/dev/null 2>&1
    svc_disable sing-box >/dev/null 2>&1
    
    rm -f /etc/nginx/conf.d/sing-box-sub.conf /etc/nginx/sites-available/sing-box-sub.conf /etc/nginx/sites-enabled/sing-box-sub.conf /etc/nginx/http.d/sing-box-sub.conf
    if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx reload >/dev/null 2>&1; else systemctl reload nginx >/dev/null 2>&1; fi

    if [[ $SYSTEM == "Alpine" ]]; then
        rm -f /etc/init.d/sing-box
    else
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
    fi
    save_iptables

    rm -rf /etc/sing-box /var/www/sing-box
    if [[ "$mode" == "all" ]]; then
        rm -f /usr/local/bin/sing-box
        rm -f /usr/bin/666 /usr/bin/hy2
    fi
}

# =================================================================
#  7. 二级管控面板与辅助工具 (节点精准卸载与配置防融毁机制)
# =================================================================
remove_node() {
    check_installed_nodes
    if [[ $has_hy2 -eq 0 && $has_vless -eq 0 ]]; then
        red "  未检测到任何已部署的节点！"
        sleep 2; return
    fi

    clear
    print_line
    green "              节点安全卸载与清理管控              "
    print_line
    echo ""
    yellow "  检测到当前系统已部署以下节点："
    [[ $has_hy2 -eq 1 ]] && green "  ▶ Hysteria 2 : 运行中"
    [[ $has_vless -eq 1 ]] && green "  ▶ VLESS      : 运行中"
    echo ""
    yellow "  请选择需要执行的卸载操作："
    echo ""
    [[ $has_hy2 -eq 1 ]] && echo -e "  ${LIGHT_GREEN}[1]${PLAIN} 仅卸载 Hysteria 2 节点 (保留 VLESS 配置)"
    [[ $has_vless -eq 1 ]] && echo -e "  ${LIGHT_GREEN}[2]${PLAIN} 仅卸载 VLESS 节点 (保留 Hysteria 2 配置)"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} 卸载全部节点与订阅服务 (清空所有入站，保留 Sing-box 核心)"
    echo ""
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} 返回主菜单"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-3]: ${PLAIN}"
    read rm_choice || return

    case $rm_choice in
        1)
            [[ $has_hy2 -eq 0 ]] && return
            close_port_by_tag "hy2-in"
            jq 'del(.inbounds[] | select(.tag=="hy2-in"))' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
            generate_client_configs
            svc_stop sing-box >/dev/null 2>&1
            svc_start sing-box >/dev/null 2>&1
            green "  [✔] Hysteria 2 节点已成功卸载！"
            sleep 2
            ;;
        2)
            [[ $has_vless -eq 0 ]] && return
            close_port_by_tag "vless-in"
            jq 'del(.inbounds[] | select(.tag=="vless-in"))' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
            generate_client_configs
            svc_stop sing-box >/dev/null 2>&1
            svc_start sing-box >/dev/null 2>&1
            green "  [✔] VLESS 节点已成功卸载！"
            sleep 2
            ;;
        3)
            clean_env "keep_core"
            green "  [✔] 所有节点配置及防火墙规则已被彻底清理！(核心已保留)"
            sleep 2
            ;;
        0) return ;;
    esac
}

global_uninstall() {
    echo ""
    red "  [警告] 这将彻底删除 Sing-box 核心、所有节点配置及 666 快捷命令！"
    echo -en " ${LIGHT_YELLOW} ▶ 是否确认全局卸载并回归没装脚本的状态？(y/n) [默认: n]: ${PLAIN}"
    read confirm || confirm="n"
    [[ -z "$confirm" ]] && confirm="n"
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        yellow "  正在全局安全卸载清理中..."
        clean_env "all"
        rm -f /root/.hy2_sub_uuid
        echo ""
        green "  全局卸载完成！系统已完全恢复至未安装脚本前的状态。"
        sleep 2
        exit 0
    else
        yellow "  已取消全局卸载。"
        sleep 2
    fi
}

edit_config() {
    clear
    if [[ ! -f /etc/sing-box/config.json ]]; then
        red "  未检测到 Sing-box 配置文件，请先安装！"
        sleep 2; return
    fi
    
    echo ""
    print_line
    green "                 当前 Sing-box 节点配置 (JSON)             "
    print_line
    echo ""
    cat /etc/sing-box/config.json
    echo ""
    print_line
    yellow "  [警告] 如果您修改了 listen_port (主端口)，"
    yellow "          脚本将无法自动更新防火墙规则！修改后请务必自行放行新端口。"
    print_line
    echo -en " ${LIGHT_YELLOW} ▶ 是否需要修改配置文件？(y/n) [默认: n]: ${PLAIN}"
    read edit_choice || exit 1
    if [[ "$edit_choice" == "y" || "$edit_choice" == "Y" ]]; then
        cp /etc/sing-box/config.json /tmp/config.json.bak
        
        if command -v nano >/dev/null; then
            nano /etc/sing-box/config.json
        elif command -v vi >/dev/null; then
            vi /etc/sing-box/config.json
        else
            red "  未找到 nano 或 vi 编辑器，请手动修改 /etc/sing-box/config.json"
        fi
        
        green "  正在验证 JSON 结构..."
        if ! jq . /etc/sing-box/config.json >/dev/null 2>&1; then
            red "  [致命错误] 修改后的配置文件不符合 JSON 规范，已被底座拦截！"
            yellow "  正在为您执行自动回滚 (Rollback)..."
            mv /tmp/config.json.bak /etc/sing-box/config.json
            sleep 3
        else
            svc_stop sing-box >/dev/null 2>&1
            svc_start sing-box >/dev/null 2>&1
            sleep 1
            if is_svc_active sing-box; then
                green "  [✔] 重启成功！新配置已生效。"
                generate_client_configs
            else
                red "  [✘] 核心拒绝启动！已恢复修改前的配置。"
                mv /tmp/config.json.bak /etc/sing-box/config.json
                svc_stop sing-box >/dev/null 2>&1
                svc_start sing-box >/dev/null 2>&1
            fi
        fi
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

config_outbound() {
    clear
    echo ""
    print_line
    green "             Sing-box 落地代理与分流 (IP 中转) 设置            "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red "  未检测到 Sing-box 配置文件，请先安装！"
        sleep 2; return
    fi

    local current_outbound=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json 2>/dev/null)
    if [[ -n "$current_outbound" && "$current_outbound" != "null" ]]; then
        local out_server=$(jq -r '.outbounds[] | select(.tag=="proxy") | .server' /etc/sing-box/config.json 2>/dev/null)
        yellow "  当前状态: [已开启] 落地代理模式 (类型: $current_outbound | 目标: $out_server)"
    else
        green "  当前状态: [未开启] 本机 IP 直连输出"
    fi
    echo ""
    
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}配置 / 修改 落地代理与智能流媒体分流${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}退回 服务器本机直连 (关闭当前落地代理)${PLAIN}"
    echo ""
    echo -e "    ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-2]: ${PLAIN}"
    read out_choice || exit 1

    case $out_choice in
        1)
            echo ""
            yellow "  ▶ 请输入中转 SOCKS5 代理 IP 或域名:"
            echo -en " ${LIGHT_YELLOW} ▶ 地址: ${PLAIN}"
            read proxy_addr || exit 1
            [[ -z "$proxy_addr" ]] && return
            
            echo -en " ${LIGHT_YELLOW} ▶ 端口: ${PLAIN}"
            read proxy_port || exit 1
            
            echo -en " ${LIGHT_YELLOW} ▶ 用户名 (留空为无鉴权): ${PLAIN}"
            read proxy_user || proxy_user=""
            
            echo -en " ${LIGHT_YELLOW} ▶ 密码 (留空为无鉴权): ${PLAIN}"
            read proxy_pass || proxy_pass=""

            echo ""
            yellow "  正在使用 jq 结构化防注入装配代理节点与路由分流规则..."
            
            # 使用 jq slurpfile 防御所有包含极特殊符号的密码与用户注入崩溃
            jq --arg addr "$proxy_addr" --arg port "$proxy_port" --arg user "$proxy_user" --arg pass "$proxy_pass" '
              if $user != "" then
                {"type":"socks","tag":"proxy","server":$addr,"server_port":($port|tonumber),"username":$user,"password":$pass}
              else
                {"type":"socks","tag":"proxy","server":$addr,"server_port":($port|tonumber)}
              end
            ' <<<'{}' > /tmp/outbound_block.json

            jq --slurpfile ob /tmp/outbound_block.json '
              del(.outbounds[] | select(.tag=="proxy")) |
              del(.route.rules[] | select(.outbound=="proxy")) |
              .outbounds += $ob |
              .route.rules = [{"domain_suffix": ["netflix.com", "nflxvideo.net", "openai.com", "chatgpt.com", "disneyplus.com"], "outbound": "proxy"}] + .route.rules
            ' /etc/sing-box/config.json > /tmp/sb_out.json
            mv /tmp/sb_out.json /etc/sing-box/config.json
            
            green "  新落地代理配置写入完毕！"
            svc_stop sing-box >/dev/null 2>&1
            svc_start sing-box >/dev/null 2>&1
            sleep 1
            if is_svc_active sing-box; then
                green "  [✔] 重启成功！静态住宅 IP 落地规则已全面生效。"
            else
                red "  [✘] 致命错误：新配置应用后服务无法启动！"
            fi
            ;;
        2)
            yellow "  正在清除中转路由配置..."
            jq 'del(.outbounds[] | select(.tag=="proxy")) | del(.route.rules[] | select(.outbound=="proxy"))' /etc/sing-box/config.json > /tmp/sb_out.json
            mv -f /tmp/sb_out.json /etc/sing-box/config.json
            
            svc_stop sing-box >/dev/null 2>&1
            svc_start sing-box >/dev/null 2>&1
            sleep 1
            green "  [✔] 重启成功！已安全退回服务器本机 IP 直连输出模式。"
            ;;
        0) return ;;
        *) red "  输入无效"; sleep 1; return ;;
    esac

    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回... ${PLAIN}"
    read temp
}

showconf() {
    realip
    local sub_port=$(cat /etc/sing-box/sub_port.txt 2>/dev/null)
    local sub_path=$(cat /etc/sing-box/sub_path.txt 2>/dev/null)
    [[ -z "$sub_port" ]] && return
    
    local sub_url="https://${PUBLIC_IP}:${sub_port}/${sub_path}"
    [[ "$PUBLIC_IP" == *":"* ]] && sub_url="https://[${PUBLIC_IP}]:${sub_port}/${sub_path}"

    local raw_url=$(cat "/var/www/sing-box/$sub_path/url.txt" 2>/dev/null)
    
    clear
    echo ""
    print_line
    green "               Sing-box 节点配置与全平台智能订阅           "
    print_line
    echo ""
    yellow "  ▶ [多核聚合智能订阅链接] (强制 HTTPS 加密传输)"
    purple "    适用客户端: Clash Verge / v2rayN / Shadowrocket 等"
    green  "    订阅地址: ${sub_url}"
    echo ""
    yellow "  ▶ [单节点直连链接]"
    purple "    适用客户端: NekoBox / v2rayNG (直接导入)"
    green  "    节点地址:"
    echo -e "${LIGHT_GREEN}${raw_url}${PLAIN}"
    echo ""
    
    print_line
    yellow "  ▶ 自助排障与安全拉取提醒 (必读)："
    echo -e "    ${LIGHT_GREEN}由于我们剥离了外部 ACME 并在订阅分发端强制挂载了 HTTPS 自签加密隧道，${PLAIN}"
    echo -e "    ${LIGHT_GREEN}您在客户端中添加该订阅时，必须开启【允许不安全的连接 (Allow Insecure)】${PLAIN}"
    echo -e "    ${LIGHT_GREEN}或【跳过证书验证 (Skip Cert Verify)】选项，否则客户端将拒绝下载订阅！${PLAIN}"
    echo -e "    ${LIGHT_PURPLE}====================================================${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

enable_bbr() {
    echo ""
    print_line
    local kernel_v=$(uname -r | cut -d. -f1)
    if [[ "$kernel_v" -lt 4 ]]; then
        red "  当前内核版本过低 ($(uname -r))，不支持开启 BBR！"
        sleep 3; return
    fi

    if ! modprobe tcp_bbr 2>/dev/null; then
        if ! grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            red "  [错误] 当前系统/内核 (可能是 LXC 容器) 彻底不支持 BBR 模块！"
            sleep 3; return
        fi
    fi
    
    local total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    [[ -z "$total_mem_kb" ]] && total_mem_kb=1048576 
    
    local page_size=$(getconf PAGESIZE)
    if ! [[ "$page_size" =~ ^[0-9]+$ ]] || [[ "$page_size" -le 0 ]]; then
        page_size=4096
    fi
    
    local mem_pages=$(( total_mem_kb / (page_size / 1024) ))
    local udp_max=$(( mem_pages / 4 ))
    [[ $udp_max -lt 65536 ]] && udp_max=65536
    local udp_mid=$(( udp_max * 3 / 4 ))
    local udp_min=$(( udp_max / 2 ))

    local current_file_max=$(sysctl -n fs.file-max || echo 0)
    local file_max_config=""
    if [[ "$current_file_max" -lt 1048576 ]]; then
        file_max_config="fs.file-max=1048576\nfs.nr_open=1048576"
    fi

    mkdir -p /etc/sysctl.d
    cat << EOF > /etc/sysctl.d/99-singbox-bbr.conf
$file_max_config
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=26214400
net.core.rmem_default=26214400
net.core.wmem_max=26214400
net.core.wmem_default=26214400
net.core.netdev_max_backlog=100000
net.core.somaxconn=65535
net.ipv4.udp_mem=$udp_min $udp_mid $udp_max
EOF
    
    sysctl -e --system >/dev/null 2>&1 || sysctl -e -p /etc/sysctl.d/99-singbox-bbr.conf >/dev/null 2>&1
    
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo ""
        green "  BBR 及极致的 UDP 缓冲区底层调优开启成功！"
    else
        echo ""
        red "  [错误] BBR 开启失败，当前内核或容器环境受限！"
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

singbox_switch() {
    clear
    echo ""
    print_line
    green "                      服务运行状态控制                      "
    print_line
    echo ""
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}启动 Sing-box 核心${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}停止 Sing-box 核心${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}重启 Sing-box 及 Nginx 分发服务${PLAIN}"
    echo ""
    echo -e "    ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-3]: ${PLAIN}"
    read switchInput || exit 1
    case $switchInput in
        1 ) svc_start sing-box >/dev/null 2>&1; green "  Sing-box 核心已启动！"; sleep 2 ;;
        2 ) svc_stop sing-box >/dev/null 2>&1; yellow "  Sing-box 核心已停止！"; sleep 2 ;;
        3 ) svc_stop sing-box >/dev/null 2>&1; svc_start sing-box >/dev/null 2>&1; if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx restart >/dev/null 2>&1; else systemctl restart nginx >/dev/null 2>&1; fi; green "  核心服务已重启！"; sleep 2 ;;
        0 ) return ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

# =================================================================
#  8. 主菜单控制 (Sing-box 极简重构版)
# =================================================================
menu() {
    local status_ui="${LIGHT_RED}● 未运行 / 异常${PLAIN}"
    is_svc_active sing-box && status_ui="${LIGHT_GREEN}● 运行中 (Active)${PLAIN}"

    clear
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "${LIGHT_GREEN}  ██████╗  ██╗   ██╗ ██████╗  ██╗       █████╗ ${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██╔══██╗ ██║   ██║ ██╔═══██╗██║      ██╔══██╗${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ███████║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ██╔══██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██████╔╝ ╚██████╔╝ ╚██████╔╝███████╗ ██║  ██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ╚═════╝   ╚══════╝  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝  ${LIGHT_YELLOW}[当前状态: ${status_ui}${LIGHT_YELLOW}]${PLAIN}"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e " ${LIGHT_GREEN}项目名称 ：Sing-box (Hy2 / VLESS) 一键部署与管理脚本 (Nginx订阅加强版)${PLAIN}"
    echo -e " ${LIGHT_PURPLE}项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch${PLAIN}"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    yellow " 脚本快捷方式：666 (已自动配置，下次可在终端直接输入 666 启动)"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 节点核心 (Hysteria 2 / VLESS)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_PURPLE}开启 BBR 及 UDP 极限并发加速 (强烈推荐)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-8]: ${PLAIN}"
    read menuInput || exit 1
    
    case $menuInput in
        1 ) inst_singbox ;;
        2 ) remove_node ;;
        3 ) singbox_switch ;;
        4 ) edit_config ;;
        5 ) config_outbound ;;
        6 ) showconf ;;
        7 ) enable_bbr ;;
        8 ) global_uninstall ;;
        0 ) exit 0 ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

while true; do
    menu
done
