#!/usr/bin/env bash
# shellcheck shell=bash

#  5. 安装交互核心流程
# =================================================================
inst_cert() {
    yellow "  系统已统一采用安全自签模式，开始生成伪装 ECC 密钥对..."
    mkdir -p /etc/sing-box
    cert_path="/etc/sing-box/cert.crt"
    key_path="/etc/sing-box/private.key"
    
    echo ""
    yellow "  请选择您的安全伪装域名 (SNI):"
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} www.bing.com (推荐, 默认)"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} www.apple.com"
    echo -e "    ${LIGHT_GREEN}[3]${PLAIN} www.microsoft.com"
    echo -e "    ${LIGHT_GREEN}[4]${PLAIN} 自定义输入"
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [1-4] (默认1): ${PLAIN}"
    read sni_choice || sni_choice=1
    [[ -z "$sni_choice" ]] && sni_choice=1
    
    local cert_sni="www.bing.com"
    case $sni_choice in
        2) cert_sni="www.apple.com" ;;
        3) cert_sni="www.microsoft.com" ;;
        4)
            echo -en " ${LIGHT_YELLOW} ▶ 请输入自定义伪装域名 (如 github.com): ${PLAIN}"
            read cert_sni || cert_sni="www.bing.com"
            [[ -z "$cert_sni" ]] && cert_sni="www.bing.com"
            ;;
    esac
    
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 36500 -key "$key_path" -out "$cert_path" -subj "/CN=$cert_sni"
    
    chmod 644 "$cert_path"
    chmod 600 "$key_path"
    echo "$cert_sni" > /etc/sing-box/cert_sni.txt
    green "  自签证书 ($cert_sni) 生成并降权授权成功！"
}


is_valid_port() {
  local port="$1"
  local min="${2:-1}"
  local max="${3:-65535}"

  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= min && port <= max ))
}

is_port_in_use() {
  local port="$1"
  local proto="${2:-tcp}"

  if [[ "$proto" == "udp" ]]; then
    ss -H -unl 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/ || $i ~ /\]:[0-9]+$/) print $i}' \
      | sed 's/.*://' \
      | grep -qx "$port"
  else
    ss -H -tnl 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/ || $i ~ /\]:[0-9]+$/) print $i}' \
      | sed 's/.*://' \
      | grep -qx "$port"
  fi
}

read_free_port() {
  local prompt="$1"
  local default_value="$2"
  local min="$3"
  local max="$4"
  local proto="$5"
  local label="${6:-端口}"
  local port=""
  local try_count=0

  READ_PORT_RESULT=""

  while true; do
    echo -en "$prompt"
    read -r port || return 1

    if [[ -z "$port" ]]; then
      if [[ "$default_value" == "random" ]]; then
        try_count=0
        while (( try_count < 50 )); do
          port="$(shuf -i "${min}-${max}" -n 1)"
          if ! is_port_in_use "$port" "$proto"; then
            break
          fi
          try_count=$((try_count + 1))
        done
      else
        port="$default_value"
      fi
    fi

    if ! is_valid_port "$port" "$min" "$max"; then
      red " [警告] ${label}无效，必须是 ${min}-${max} 的数字。"
      continue
    fi

    if is_port_in_use "$port" "$proto"; then
      red " [警告] ${proto^^} 端口 $port 已被占用，请重新输入。"
      continue
    fi

    READ_PORT_RESULT="$port"
    return 0
  done
}

inst_sub_port(){
    echo ""
    local history_port=""
    [[ -f /etc/sing-box/sub_port.txt ]] && history_port=$(cat /etc/sing-box/sub_port.txt)
    
    if [[ -n "$history_port" ]]; then
        echo -en " ${LIGHT_YELLOW} ▶ 检测到历史订阅端口 [${history_port}]，是否沿用以保持订阅链接不变？(y/n) [默认: y]: ${PLAIN}"
        read use_hist || use_hist="y"
        [[ -z "$use_hist" ]] && use_hist="y"
        if [[ "$use_hist" == "y" || "$use_hist" == "Y" ]]; then
            sub_port_input=$history_port
            green " 沿用历史订阅 HTTP 端口: $sub_port_input"
            open_port "$sub_port_input" "tcp" "sub"
            return
        fi
    fi

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
    green " 订阅 HTTP 端口已设置为: $sub_port_input"
    open_port $sub_port_input "tcp" "sub"
    echo "$sub_port_input" > /etc/sing-box/sub_port.txt
}

setup_singbox_service() {
    yellow "  正在装配 Sing-box 系统级守护进程 (挂载高强度沙盒防御)..."
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
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "google",
        "server": "8.8.8.8",
        "server_port": 53
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      {
        "ip_cidr": [ "169.254.0.0/16", "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7", "fe80::/10" ],
        "action": "route",
        "outbound": "block"
      }
    ]
  }
}
EOF
}


migrate_legacy_dns_config() {
    # 兼容 sing-box 1.12+：自动把旧版 dns.servers[].address 迁移为新版 server/type 写法
    # 注意：DNS 服务器不要写 detour: direct。新版 sing-box 会报：detour to an empty direct outbound makes no sense。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.dns.servers[]? | select((has("address")) and ((has("type") | not) or (.type == null)))' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到旧版 DNS 配置，正在自动迁移为 sing-box 1.12+ 新格式..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.dns.$(date +%F-%H%M%S)" || true

        jq '
          .dns.servers |= map(
            if (has("address") and ((has("type") | not) or (.type == null))) then
              . as $old |
              {
                "type": "udp",
                "tag": ($old.tag // "google"),
                "server": $old.address,
                "server_port": ($old.server_port // 53)
              }
            else
              .
            end
          )
        ' /etc/sing-box/config.json > /tmp/sb_dns.json && mv /tmp/sb_dns.json /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] DNS 配置迁移完成。"
    fi
}

fix_dns_detour_direct_config() {
    # 修复已经被迁移成新 DNS 但仍残留 detour: direct 的配置。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.dns.servers[]? | select((.detour // "") == "direct")' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到 DNS 残留 detour=direct，正在移除以兼容新版 sing-box..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.dns-detour.$(date +%F-%H%M%S)" || true
        jq '(.dns.servers[]? | select((.detour // "") == "direct")) |= del(.detour)'           /etc/sing-box/config.json > /tmp/sb_dns_detour.json && mv /tmp/sb_dns_detour.json /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] DNS detour 兼容修复完成。"
    fi
}

migrate_legacy_route_config() {
    # sing-box 1.11+ 推荐 Route Action；旧配置只有 outbound 时补 action=route。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.route.rules[]? | select((has("outbound")) and ((has("action") | not) or (.action == null)))' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到旧版路由规则，正在补充 action=route..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.route.$(date +%F-%H%M%S)" || true
        jq '(.route.rules[]? | select((has("outbound")) and ((has("action") | not) or (.action == null))) | .action) = "route"'           /etc/sing-box/config.json > /tmp/sb_route.json && mv /tmp/sb_route.json /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] 路由规则兼容修复完成。"
    fi
}

fix_listen_for_no_ipv6() {
    # 某些精简 Alpine/LXC 没有 IPv6，listen="::" 会导致服务无法监听。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    [[ -f /proc/net/if_inet6 ]] && return 0

    if jq -e '.inbounds[]? | select(.listen == "::")' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  当前系统未启用 IPv6，正在把监听地址从 :: 改为 0.0.0.0..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.listen.$(date +%F-%H%M%S)" || true
        jq '(.inbounds[]? | select(.listen == "::") | .listen) = "0.0.0.0"'           /etc/sing-box/config.json > /tmp/sb_listen.json && mv /tmp/sb_listen.json /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] 监听地址兼容修复完成。"
    fi
}

ensure_singbox_core() {
    if [[ -x /usr/local/bin/sing-box ]]; then
        return 0
    fi

    yellow "  未检测到 /usr/local/bin/sing-box，正在重新拉取核心..."
    local arch=$(uname -m)
    local sb_arch=""
    case "$arch" in
        x86_64 | amd64)      sb_arch="amd64" ;;
        aarch64 | arm64)     sb_arch="arm64" ;;
        armv7* | armv6*)     sb_arch="armv7" ;;
        i386 | i686)         sb_arch="386" ;;
        s390x)               sb_arch="s390x" ;;
        *) red " [致命错误] Sing-box 暂不支持您的 CPU 架构: $arch！"; return 1 ;;
    esac

    local sb_version=$(curl -sI -m 10 "https://github.com/SagerNet/sing-box/releases/latest" | grep -i location | awk -F '/' '{print $NF}' | tr -d '\r\n')
    [[ -z "$sb_version" || "$sb_version" == "null" ]] && sb_version="v1.12.0"
    local dl_url="https://github.com/SagerNet/sing-box/releases/download/${sb_version}/sing-box-${sb_version#v}-linux-${sb_arch}.tar.gz"

    mkdir -p /usr/local/bin
    rm -rf /tmp/sing-box*
    wget --timeout=15 --tries=3 -O /tmp/sing-box.tar.gz "$dl_url" || wget --timeout=15 --tries=3 -O /tmp/sing-box.tar.gz "https://ghfast.top/$dl_url"
    if [[ ! -s /tmp/sing-box.tar.gz ]]; then
        red " [致命错误] Sing-box 核心下载失败！请检查网络。"
        return 1
    fi

    tar -xzf /tmp/sing-box.tar.gz -C /tmp/ || { red " [致命错误] Sing-box 核心解压失败！"; return 1; }
    local extract_dir=$(find /tmp/ -type d -name "sing-box-*-linux-${sb_arch}" | head -n 1)
    if [[ -n "$extract_dir" && -f "$extract_dir/sing-box" ]]; then
        mv -f "$extract_dir/sing-box" /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        green "  [✔] Sing-box ($sb_version | $sb_arch) 核心已恢复。"
        rm -rf /tmp/sing-box*
        return 0
    fi

    red " [致命错误] Sing-box 核心解压后未找到二进制文件。"
    rm -rf /tmp/sing-box*
    return 1
}

normalize_singbox_config() {
    migrate_legacy_dns_config
    fix_dns_detour_direct_config
    migrate_legacy_route_config
    fix_listen_for_no_ipv6
}

check_singbox_config() {
    ensure_singbox_core || return 1
    normalize_singbox_config
    if [[ -x /usr/local/bin/sing-box && -f /etc/sing-box/config.json ]]; then
        yellow "  正在执行 sing-box 配置校验，完整输出如下："
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json 2>&1 | tee /tmp/sing-box-check.log
        local rc=${PIPESTATUS[0]}
        if [[ $rc -ne 0 ]]; then
            red "  [致命错误] Sing-box 配置校验失败，服务未重启。"
            return $rc
        fi
        green "  [✔] Sing-box 配置校验通过。"
    else
        red "  [致命错误] 未找到 /usr/local/bin/sing-box 或 /etc/sing-box/config.json。"
        return 1
    fi
    return 0
}

restart_singbox_checked() {
    check_singbox_config || return 1
    if is_svc_active sing-box; then
        svc_restart sing-box
    else
        svc_start sing-box
    fi
    sleep 1
    if ! is_svc_active sing-box; then
        red "  [✘] Sing-box 启动失败。最近日志如下："
        if [[ $SYSTEM == "Alpine" ]]; then
            tail -n 80 /var/log/sing-box.log 2>/dev/null || true
        else
            journalctl -u sing-box -n 80 --no-pager 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

inst_hysteria2() {
    local is_first=1
    [[ -f /etc/sing-box/config.json ]] && is_first=0

    if [[ $is_first -eq 1 ]]; then
        inst_cert
        inst_sub_port
        setup_singbox_service
        build_base_json
    fi
    
    echo ""
    print_line
    yellow "  Hysteria 2 主端口与网络配置"
    read_free_port " ${LIGHT_YELLOW} ▶ 设置 Hysteria 2 主端口 (UDP) [10000-65535] (回车随机): ${PLAIN}" "random" 10000 65535 "udp" "Hysteria 2 主端口" || return 1
port="$READ_PORT_RESULT"
green " 节点主端口已设置为: $port (UDP)"
open_port "$port" "udp" "hy2-in"
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
    
    local listen_addr="::"
    [[ ! -f /proc/net/if_inet6 ]] && listen_addr="0.0.0.0"

    jq --arg p "$port" --arg pwd "$auth_pwd" --arg cp "/etc/sing-box/cert.crt" --arg kp "/etc/sing-box/private.key" --arg listen "$listen_addr" '
    .inbounds += [{
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": $listen,
      "listen_port": ($p | tonumber),
      "users": [{"password": $pwd}],
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cp, "key_path": $kp }
    }]' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    
    if [[ -n "$obfs_pwd" ]]; then
        jq --arg obfs "$obfs_pwd" '( .inbounds[] | select(.tag=="hy2-in") ) += { "obfs": {"type": "salamander", "password": $obfs} }' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    fi
    
    chmod 600 /etc/sing-box/config.json
    svc_enable sing-box
    restart_singbox_checked || return 1
    generate_client_configs
    
    echo ""
    green "  [✔] Hysteria 2 服务端已追加部署成功！"
    sleep 2
}

inst_vless_reality() {
    local is_first=1
    [[ -f /etc/sing-box/config.json ]] && is_first=0

    if [[ $is_first -eq 1 ]]; then
        inst_cert
        inst_sub_port
        setup_singbox_service
        build_base_json
    fi
    
    echo ""
    print_line
    yellow "  VLESS + Reality 端口与特征配置"
    read_free_port " ${LIGHT_YELLOW} ▶ 请设置 VLESS 主端口 (TCP) [1-65535] (回车默认 443，可自定义): ${PLAIN}" "443" 1 65535 "tcp" "VLESS 主端口" || return 1
port="$READ_PORT_RESULT"
green " 节点主端口已设置为: $port (TCP)"
open_port "$port" "tcp" "vless-in"
echo ""
    local v_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.microsoft.com")
    yellow "  VLESS Reality 伪装域名已自动继承基础设定: $v_sni"
    
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
    
    local listen_addr="::"
    [[ ! -f /proc/net/if_inet6 ]] && listen_addr="0.0.0.0"

    yellow "  正在写入 VLESS Reality 推荐参数：Vision + Reality + TCP Fast Open + 自适应监听..."
    jq --arg p "$port" --arg uuid "$v_uuid" --arg priv "$v_private_key" --arg sid "$v_short_id" --arg sni "$v_sni" --arg listen "$listen_addr" '
    .inbounds += [{
      "type": "vless",
      "tag": "vless-in",
      "listen": $listen,
      "listen_port": ($p | tonumber),
      "tcp_fast_open": true,
      "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": { "server": $sni, "server_port": 443 },
          "private_key": $priv,
          "short_id": [$sid]
        }
      }
    }]' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
    
    chmod 600 /etc/sing-box/config.json
    svc_enable sing-box
    restart_singbox_checked || return 1
    generate_client_configs
    
    echo ""
    green "  [✔] VLESS + Reality 服务端已追加部署成功！"
    yellow "  已自动写入 VLESS Reality 推荐配置：Vision + Reality + TCP Fast Open + 自适应监听。"
    yellow "  端口保持您安装时的自定义选择；如需 TCP 系统层加速，可在主菜单 [7] 开启 BBR。"
    sleep 2
}

inst_singbox() {
    check_env
    normalize_singbox_config
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

