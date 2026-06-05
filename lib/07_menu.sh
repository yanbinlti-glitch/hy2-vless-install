#!/usr/bin/env bash
# shellcheck shell=bash

# 8. 主菜单控制
# =================================================================



main_status_get_public_ipv4() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
}

main_status_get_public_ipv6() {
    ip -o -6 addr show scope global 2>/dev/null \
        | awk '$2 != "wgcf" && $2 !~ /warp/i && $4 !~ /^fd/ {split($4,a,"/"); print a[1]; exit}'
}

main_status_get_warp_iface() {
    local configured candidate

    configured=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null | head -n1)
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
        latest=$(curl -fsSL --connect-timeout 3 https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
            | grep -m1 '"tag_name"' \
            | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
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

    if [[ ! -f /etc/sing-box/config.json ]] || ! command -v jq >/dev/null 2>&1; then
        yellow " 节点安装信息: 未检测到配置文件"
        return 0
    fi

    hy2_port=$(jq -r '.inbounds[]? | select(.tag=="hy2-in") | .listen_port // empty' /etc/sing-box/config.json 2>/dev/null)
    vless_port=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .listen_port // empty' /etc/sing-box/config.json 2>/dev/null)

    if [[ -z "$hy2_port" && -z "$vless_port" ]]; then
        yellow " 节点安装信息: 未检测到 Hy2 / VLESS 入站"
        return 0
    fi

    echo -e " ${LIGHT_CYAN}Sing-box 节点安装信息:${PLAIN}"

    if [[ -n "$vless_port" && "$vless_port" != "null" ]]; then
        vless_sni=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config.json 2>/dev/null)
        vless_flow=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .users[0].flow // empty' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$vless_sni" || "$vless_sni" == "null" ]] && vless_sni="未读取"
        [[ -z "$vless_flow" || "$vless_flow" == "null" ]] && vless_flow="xtls-rprx-vision"

        echo -e " ${LIGHT_GREEN} ✔ [ VLESS-Reality ]${PLAIN} 端口:${LIGHT_YELLOW}${vless_port}${PLAIN}  Reality域名:${LIGHT_YELLOW}${vless_sni}${PLAIN}  flow:${LIGHT_YELLOW}${vless_flow}${PLAIN}"
    fi

    if [[ -n "$hy2_port" && "$hy2_port" != "null" ]]; then
        hy2_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "未读取")
        hy2_hop=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')
        [[ -z "$hy2_hop" ]] && hy2_hop="未开启"

        echo -e " ${LIGHT_GREEN} ✔ [ Hysteria-2   ]${PLAIN} 端口:${LIGHT_YELLOW}${hy2_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${hy2_sni}${PLAIN}  跳跃端口:${LIGHT_YELLOW}${hy2_hop}${PLAIN}"
    fi
}

main_realtime_status_panel() {
    local os_name kernel arch virt bbr ipv4 ipv6 warp_iface warp_ipv6 sb_ver sb_latest svc_text script_ver

    os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    [[ -z "$os_name" ]] && os_name="unknown"

    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    virt=$(main_status_detect_virtualization)
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    ipv4=$(main_status_get_public_ipv4)
    ipv6=$(main_status_get_public_ipv6)
    warp_iface=$(main_status_get_warp_iface)
    script_ver="${HY2_VLESS_VERSION:-dev}"
    sb_ver=$(main_status_singbox_version)
    sb_latest=$(main_status_latest_singbox_version)

    if is_svc_active sing-box; then
        svc_text="${LIGHT_GREEN}运行中${PLAIN}"
    else
        svc_text="${LIGHT_RED}未运行 / 异常${PLAIN}"
    fi

    [[ -z "$ipv4" ]] && ipv4="未检测到"
    [[ -z "$ipv6" ]] && ipv6="无公网IPv6"

    if [[ -n "$warp_iface" ]]; then
        warp_ipv6=$(ip -6 addr show dev "$warp_iface" scope global 2>/dev/null | awk '/inet6/ {print $2; exit}' | cut -d/ -f1)
        [[ -n "$warp_ipv6" ]] && warp_iface="${warp_iface} (${warp_ipv6})"
    else
        warp_iface="未检测到"
    fi

    echo -e " ${LIGHT_CYAN}────────────────────────────────────────────────────────────────────${PLAIN}"
    echo -e " ${LIGHT_CYAN}实时状态面板${PLAIN}"
    echo -e " ${LIGHT_CYAN}────────────────────────────────────────────────────────────────────${PLAIN}"
    echo -e " ${LIGHT_YELLOW}脚本版本:${PLAIN} v${script_ver}    ${LIGHT_YELLOW}Sing-box内核:${PLAIN} ${sb_ver}    ${LIGHT_YELLOW}最新正式版:${PLAIN} ${sb_latest}"
    echo -e " ${LIGHT_YELLOW}系统:${PLAIN} ${os_name}    ${LIGHT_YELLOW}内核:${PLAIN} ${kernel}    ${LIGHT_YELLOW}架构:${PLAIN} ${arch}    ${LIGHT_YELLOW}虚拟化:${PLAIN} ${virt}"
    echo -e " ${LIGHT_YELLOW}BBR算法:${PLAIN} ${bbr}    ${LIGHT_YELLOW}Sing-box状态:${PLAIN} ${svc_text}"
    echo -e " ${LIGHT_YELLOW}本机IPv4:${PLAIN} ${ipv4}    ${LIGHT_YELLOW}本机IPv6:${PLAIN} ${ipv6}"
    echo -e " ${LIGHT_YELLOW}WARP接口:${PLAIN} ${warp_iface}"
    echo ""
    main_status_show_node_info
    echo -e " ${LIGHT_CYAN}────────────────────────────────────────────────────────────────────${PLAIN}"
    echo ""
}

menu() {
  local status_ui="${LIGHT_RED}● 未运行 / 异常${PLAIN}"
  local version_ui="${HY2_VLESS_VERSION:-dev}"

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
   echo -e " ${LIGHT_YELLOW}当前版本 ：v${version_ui}${PLAIN}"
  echo -e " ${LIGHT_GREEN}项目名称 ：Sing-box (Hy2 / VLESS) 一键部署与管理脚本 (Nginx订阅加强版)${PLAIN}"
  echo -e " ${LIGHT_PURPLE}项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch${PLAIN}"
  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  main_realtime_status_panel
    yellow " 脚本快捷方式：666 (已自动配置，下次可在终端直接输入 666 启动)"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

  echo -e " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 节点核心 (Hysteria 2 / VLESS)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  echo -e " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
  echo -e " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
  echo -e " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  echo -e " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  echo -e " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_CYAN}检查 / 在线更新脚本${PLAIN}"
    echo -e " ${LIGHT_GREEN}[11]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  echo -e " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-11]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in
    1 ) inst_singbox ;;
    2 ) remove_node ;;
    3 ) singbox_switch ;;
    4 ) config_modify_menu ;;
    5 ) config_outbound ;;
    6 ) showconf ;;
    7 ) enable_bbr ;;
    8 ) global_uninstall ;;
    9 ) quick_repair_and_status ;;
    10 ) self_update ;; 11 ) warp_ipv6_route_menu ;;
    0 ) exit 0 ;;
    * ) red " 输入无效"; sleep 1 ;;
  esac
}
