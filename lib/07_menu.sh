#!/usr/bin/env bash
# V1.5.8_PROBE_FIX
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
# 8. 主菜单控制
# =================================================================



main_status_get_public_ipv4() {
  local ip=""

  if command -v curl >/dev/null 2>&1; then
    ip=$(
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --ipv4 \
        --proto '=https' \
        --tlsv1.2 \
        --connect-timeout 4 \
        --max-time 6 \
        --retry 2 \
        "https://api.ipify.org" \
        2>/dev/null ||
        true
    )
  fi

  if [[ -z "$ip" ]] &&
     command -v wget >/dev/null 2>&1
  then
    ip=$(
      wget \
        -qO- \
        -T 6 \
        "https://api.ipify.org" \
        2>/dev/null ||
        true
    )
  fi

  ip="$(
    printf '%s' "$ip" |
      tr -d '[:space:]'
  )"

  if [[ "$ip" == *:* ]] ||
     ! declare -F valid_ip_literal >/dev/null ||
     ! valid_ip_literal "$ip"
  then
    ip=""
  fi

  printf '%s\n' "$ip"
}

main_status_get_public_ipv6() {
  local ip=""

  if command -v curl >/dev/null 2>&1; then
    ip=$(
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --ipv6 \
        --proto '=https' \
        --tlsv1.2 \
        --connect-timeout 4 \
        --max-time 6 \
        --retry 2 \
        "https://api6.ipify.org" \
        2>/dev/null ||
        true
    )
  fi

  if [[ -z "$ip" ]] &&
     command -v wget >/dev/null 2>&1
  then
    ip=$(
      wget \
        -qO- \
        -T 6 \
        "https://api6.ipify.org" \
        2>/dev/null ||
        true
    )
  fi

  ip="$(
    printf '%s' "$ip" |
      tr -d '[:space:]'
  )"

  if [[ "$ip" != *:* ]] ||
     ! declare -F valid_ip_literal >/dev/null ||
     ! valid_ip_literal "$ip"
  then
    ip=""
  fi

  printf '%s\n' "$ip"
}

main_status_get_warp_iface() {
    local configured candidate

    configured=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null | head -n1)
    if [[ -n "$configured" && "$configured" != "null" ]] && ip link show "$configured" >/dev/null 2>&1; then
        echo "$configured"
        return 0
    fi

    for candidate in wgcf warp CloudflareWARP; do
        if ip link show "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    ip -o link show 2>/dev/null \
        | awk -F': ' '{print $2}' \
        | grep -Ei 'warp|wgcf|cloudflare' \
        | head -n1
}

main_status_singbox_version() {
    if [[ -x /usr/local/bin/sing-box ]]; then
        /usr/local/bin/sing-box version 2>/dev/null \
            | head -n1 \
            | sed 's/^sing-box version //'
    else
        echo "未安装"
    fi
}

main_status_latest_singbox_version() {
    local latest=""
    if command -v curl >/dev/null 2>&1; then
        latest=$(curl -sI -m 6 https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null | grep -i location | awk -F '/' '{print $NF}' | tr -d '
')
    fi
    [[ -n "$latest" ]] && echo "$latest" || echo "获取失败"
}

main_status_detect_virtualization() {
    local virt=""

    virt=$(systemd-detect-virt 2>/dev/null || true)
    [[ "$virt" == "none" ]] && virt=""

    if [[ -z "$virt" ]] && command -v virt-what >/dev/null 2>&1; then
        virt=$(virt-what 2>/dev/null | head -n1)
    fi

    [[ -n "$virt" ]] && echo "$virt" || echo "unknown"
}

main_status_show_node_info() {
    local hy2_port hy2_sni hy2_hop vless_port vless_sni vless_flow

    if [[ ! -f /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json ]] || ! command -v jq >/dev/null 2>&1; then
        yellow " 节点安装信息: 未检测到配置文件"
        return 0
    fi

    hy2_port=$(jq -r '.inbounds[]? | select((.tag // "")=="hy2-in" or (.type // "")=="hysteria2") | .listen_port // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
    vless_port=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .listen_port // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)

    if [[ -z "$hy2_port" && -z "$vless_port" ]]; then
        yellow " 节点安装信息: 未检测到 Hy2 / VLESS 入站"
        return 0
    fi

    printf "%b
" " ${LIGHT_CYAN}Sing-box 节点安装信息:${PLAIN}"

    if [[ -n "$vless_port" && "$vless_port" != "null" ]]; then
        vless_sni=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
        vless_flow=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .users[0].flow // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
        [[ -z "$vless_sni" || "$vless_sni" == "null" ]] && vless_sni="未读取"
        [[ -z "$vless_flow" || "$vless_flow" == "null" ]] && vless_flow="xtls-rprx-vision"

        printf "%b
" " ${LIGHT_GREEN} ✔ [ VLESS-Reality ]${PLAIN} 端口:${LIGHT_YELLOW}${vless_port}${PLAIN}  Reality域名:${LIGHT_YELLOW}${vless_sni}${PLAIN}  flow:${LIGHT_YELLOW}${vless_flow}${PLAIN}"
    fi

        if [[ -n "$hy2_port" && "$hy2_port" != "null" ]]; then
        hy2_sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "未读取")
        hy2_hop=$(cat /etc/sing-box/hy2_hop_ports${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null | tr -d '[:space:]')
        [[ -z "$hy2_hop" ]] && hy2_hop="未开启"

        printf "%b
" " ${LIGHT_GREEN} ✔ [ Hysteria-2   ]${PLAIN} 端口:${LIGHT_YELLOW}${hy2_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${hy2_sni}${PLAIN}  跳跃端口:${LIGHT_YELLOW}${hy2_hop}${PLAIN}"
    fi

    local tuic_port=$(jq -r '.inbounds[]? | select(.tag=="tuic-in") | .listen_port // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
    if [[ -n "$tuic_port" && "$tuic_port" != "null" ]]; then
        local tuic_sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "未读取")
        printf "%b
" " ${LIGHT_GREEN} ✔ [ TUIC v5      ]${PLAIN} 端口:${LIGHT_YELLOW}${tuic_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${tuic_sni}${PLAIN}  拥塞控制:${LIGHT_YELLOW}bbr${PLAIN}"
    fi
  echo ""
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  printf "%b\n" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 节点核心 (Hysteria 2 / VLESS / TUIC)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出面板${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-10]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in
      0 ) exit 0 ;;
      1 ) inst_singbox ;;
      2 ) remove_node ;;
      3 ) singbox_switch ;;
      4 ) config_modify_menu ;;
      5 ) warp_ipv6_route_menu ;;
      6 ) config_outbound ;;
      7 ) showconf ;;
      8 ) enable_bbr ;;
      9 ) quick_repair_and_status ;;
      10 ) global_uninstall ;;
      * ) red " 输入无效"; sleep 1 ;;
  esac
}


