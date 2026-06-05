#!/usr/bin/env bash
# shellcheck shell=bash

# ============================================================================
# 07. 主菜单控制
# ============================================================================

ui_line() {
    echo -e "${LIGHT_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
}

ui_section() {
    local title="$1"
    echo -e "${LIGHT_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━ ${title} ━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
}

ui_get_os_name() {
    local os_name
    os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
    [[ -n "$os_name" ]] && echo "$os_name" || echo "unknown"
}

ui_get_ipv4() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
}

ui_get_ipv6() {
    ip -o -6 addr show scope global 2>/dev/null \
        | awk '$2 !~ /^(wgcf|warp|CloudflareWARP)$/ && $4 !~ /^fd/ {split($4,a,"/"); print a[1]; exit}'
}

ui_get_warp_iface() {
    local configured candidate

    if [[ -f /etc/sing-box/config.json ]] && command -v jq >/dev/null 2>&1; then
        configured=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null | head -n1)
        if [[ -n "$configured" && "$configured" != "null" ]] && ip link show "$configured" >/dev/null 2>&1; then
            echo "$configured"
            return 0
        fi
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

ui_get_singbox_version() {
    if [[ -x /usr/local/bin/sing-box ]]; then
        /usr/local/bin/sing-box version 2>/dev/null \
            | head -n1 \
            | sed 's/^sing-box version //'
    else
        echo "未安装"
    fi
}

ui_get_singbox_latest() {
    local latest=""

    if command -v curl >/dev/null 2>&1; then
        latest=$(curl -fsSL --connect-timeout 3 https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
            | grep -m1 '"tag_name"' \
            | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    fi

    [[ -n "$latest" ]] && echo "$latest" || echo "获取失败"
}

ui_get_virtualization() {
    local virt=""

    virt=$(systemd-detect-virt 2>/dev/null || true)
    [[ "$virt" == "none" ]] && virt=""

    if [[ -z "$virt" ]] && command -v virt-what >/dev/null 2>&1; then
        virt=$(virt-what 2>/dev/null | head -n1)
    fi

    [[ -n "$virt" ]] && echo "$virt" || echo "unknown"
}

ui_get_bbr() {
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
}

ui_show_node_status() {
    local hy2_port hy2_sni hy2_hop
    local vless_port vless_sni vless_flow
    local warp_iface warp_state warp_domains

    if [[ ! -f /etc/sing-box/config.json ]] || ! command -v jq >/dev/null 2>&1; then
        echo -e "  ${LIGHT_RED}✘ Hysteria2      : 未安装${PLAIN}"
        echo -e "  ${LIGHT_RED}✘ VLESS Reality  : 未安装${PLAIN}"
        echo -e "  ${LIGHT_RED}✘ WARP IPv6分流  : 未开启${PLAIN}"
        return 0
    fi

    hy2_port=$(jq -r '.inbounds[]? | select(.tag=="hy2-in") | .listen_port // empty' /etc/sing-box/config.json 2>/dev/null)
    vless_port=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .listen_port // empty' /etc/sing-box/config.json 2>/dev/null)

    if [[ -n "$hy2_port" && "$hy2_port" != "null" ]]; then
        hy2_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "未读取")
        hy2_hop=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')
        [[ -z "$hy2_hop" ]] && hy2_hop="未开启"
        echo -e "  ${LIGHT_GREEN}✔ Hysteria2      ${PLAIN}: UDP ${LIGHT_YELLOW}${hy2_port}${PLAIN} | 证书 ${LIGHT_YELLOW}${hy2_sni}${PLAIN} | 跳跃端口 ${LIGHT_YELLOW}${hy2_hop}${PLAIN}"
    else
        echo -e "  ${LIGHT_RED}✘ Hysteria2      : 未安装${PLAIN}"
    fi

    if [[ -n "$vless_port" && "$vless_port" != "null" ]]; then
        vless_sni=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config.json 2>/dev/null)
        vless_flow=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .users[0].flow // empty' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$vless_sni" || "$vless_sni" == "null" ]] && vless_sni="未读取"
        [[ -z "$vless_flow" || "$vless_flow" == "null" ]] && vless_flow="xtls-rprx-vision"
        echo -e "  ${LIGHT_GREEN}✔ VLESS Reality  ${PLAIN}: TCP ${LIGHT_YELLOW}${vless_port}${PLAIN} | SNI  ${LIGHT_YELLOW}${vless_sni}${PLAIN} | ${LIGHT_YELLOW}${vless_flow}${PLAIN}"
    else
        echo -e "  ${LIGHT_RED}✘ VLESS Reality  : 未安装${PLAIN}"
    fi

    warp_iface=$(ui_get_warp_iface)
    warp_domains=$(jq -r '.route.rules[]? | select(.outbound=="warp-ipv6") | .domain_suffix[]? // empty' /etc/sing-box/config.json 2>/dev/null | paste -sd "," -)

    if jq -e '.outbounds[]? | select(.tag=="warp-ipv6")' /etc/sing-box/config.json >/dev/null 2>&1; then
        warp_state="已开启"
        [[ -n "$warp_domains" ]] && warp_state="${warp_state} | ${warp_domains}"
        echo -e "  ${LIGHT_GREEN}✔ WARP IPv6分流  ${PLAIN}: ${LIGHT_YELLOW}${warp_state}${PLAIN} | 接口 ${LIGHT_YELLOW}${warp_iface:-未检测到}${PLAIN}"
    else
        echo -e "  ${LIGHT_RED}✘ WARP IPv6分流  : 未开启${PLAIN}"
    fi
}

ui_realtime_dashboard() {
    local os_name kernel arch virt bbr ipv4 ipv6 warp_iface sb_ver sb_latest svc_text script_ver

    script_ver="${HY2_VLESS_VERSION:-dev}"
    os_name=$(ui_get_os_name)
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    virt=$(ui_get_virtualization)
    bbr=$(ui_get_bbr)
    ipv4=$(ui_get_ipv4)
    ipv6=$(ui_get_ipv6)
    warp_iface=$(ui_get_warp_iface)
    sb_ver=$(ui_get_singbox_version)
    sb_latest=$(ui_get_singbox_latest)

    [[ -z "$ipv4" ]] && ipv4="未检测到"
    [[ -z "$ipv6" ]] && ipv6="无公网IPv6"
    [[ -z "$warp_iface" ]] && warp_iface="未检测到"

    if is_svc_active sing-box; then
        svc_text="${LIGHT_GREEN}运行中${PLAIN}"
    else
        svc_text="${LIGHT_RED}未运行${PLAIN}"
    fi

    ui_line
    echo -e "  ${LIGHT_GREEN}HY2-VLESS-INSTALL${PLAIN}  ${LIGHT_YELLOW}v${script_ver}${PLAIN}"
    ui_line
    echo ""
    echo -e "  ${LIGHT_CYAN}系统${PLAIN}  ${os_name} | Kernel ${kernel} | ${arch} | ${virt} | BBR:${bbr}"
    echo -e "  ${LIGHT_CYAN}网络${PLAIN}  IPv4: ${ipv4} | IPv6: ${ipv6} | WARP: ${warp_iface}"
    echo -e "  ${LIGHT_CYAN}内核${PLAIN}  sing-box: ${sb_ver} | 最新正式版: ${sb_latest} | 服务: ${svc_text}"
    echo ""
    ui_section "节点状态"
    ui_show_node_status
    echo ""
}

menu() {
    local menuInput

    while true; do
        clear

        ui_realtime_dashboard

        ui_section "功能菜单"
        echo -e "  ${LIGHT_GREEN}[1]${PLAIN} 安装 / 添加节点              ${LIGHT_GREEN}[2]${PLAIN} 节点安全卸载与清理"
        echo -e "  ${LIGHT_GREEN}[3]${PLAIN} Sing-box 服务管理            ${LIGHT_GREEN}[4]${PLAIN} 配置 / 证书 / Hy2跳跃端口"
        echo ""
        echo -e "  ${LIGHT_GREEN}[5]${PLAIN} 出口落地代理与分流          ${LIGHT_GREEN}[6]${PLAIN} 节点信息 / 订阅链接"
        echo -e "  ${LIGHT_GREEN}[7]${PLAIN} BBR / TFO / UDP 加速         ${LIGHT_GREEN}[8]${PLAIN} 全局卸载脚本"
        echo ""
        echo -e "  ${LIGHT_GREEN}[9]${PLAIN} 一键兼容修复 / 状态诊断     ${LIGHT_GREEN}[10]${PLAIN} 检查 / 在线更新脚本"
        echo -e "  ${LIGHT_GREEN}[11]${PLAIN} WARP IPv6 域名分流          ${LIGHT_GREEN}[0]${PLAIN} 退出脚本"
        echo ""
        ui_line
        echo -en "  ${LIGHT_YELLOW}请输入选项 [0-11]: ${PLAIN}"
        read -r menuInput || exit 1

        case "$menuInput" in
            1) inst_singbox ;;
            2) remove_node ;;
            3) singbox_switch ;;
            4) config_modify_menu ;;
            5) config_outbound ;;
            6) showconf ;;
            7) enable_bbr ;;
            8) global_uninstall ;;
            9) quick_repair_and_status ;;
            10) self_update ;;
            11) warp_ipv6_route_menu ;;
            0) exit 0 ;;
            *) red " 输入无效"; sleep 1 ;;
        esac
    done
}
