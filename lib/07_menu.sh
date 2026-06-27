menu() {
    clear
    printf "\n"
    printf "%b\n" " \033[1;36m==================================================================================\033[0m"
    printf "%b\n" " \033[1;32m      Hysteria 2 + VLESS + TUIC 终极面板 \033[0m"
    printf "%b\n" " \033[1;36m==================================================================================\033[0m"
    printf "%b\n" " ${LIGHT_YELLOW}当前版本 ：v${version_ui}${PLAIN}"
    printf "%b\n" " ${LIGHT_CYAN}当前实例 ：Instance ${HY2_INSTANCE_ID} ${HY2_INSTANCE_SUFFIX}${PLAIN}"
    echo ""

    local hy2_port=$(jq -r '.listen | split(":")[1]' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
    if [[ -n "$hy2_port" && "$hy2_port" != "null" ]]; then
        local hy2_sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "未读取")
        local hy2_hop=$(cat /etc/sing-box/hy2_hop_ports${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null | tr -d '[:space:]')
        [[ -z "$hy2_hop" ]] && hy2_hop="未开启"
        printf "%b\n" " ${LIGHT_GREEN} ✔ [ Hysteria-2   ]${PLAIN} 端口:${LIGHT_YELLOW}${hy2_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${hy2_sni}${PLAIN}  跳跃端口:${LIGHT_YELLOW}${hy2_hop}${PLAIN}"
    fi

    if jq -e '.inbounds[] | select(.tag=="vless-in")' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json >/dev/null 2>&1; then
        local vless_port=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .listen_port' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
        local vless_sni=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.server_name' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
        printf "%b\n" " ${LIGHT_GREEN} ✔ [ VLESS+Reality]${PLAIN} 端口:${LIGHT_YELLOW}${vless_port}${PLAIN}  伪装域名:${LIGHT_YELLOW}${vless_sni}${PLAIN}"
    fi

    local tuic_port=$(jq -r '.inbounds[]? | select(.tag=="tuic-in") | .listen_port // empty' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null)
    if [[ -n "$tuic_port" && "$tuic_port" != "null" ]]; then
        local tuic_sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "未读取")
        printf "%b\n" " ${LIGHT_GREEN} ✔ [ TUIC v5      ]${PLAIN} 端口:${LIGHT_YELLOW}${tuic_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${tuic_sni}${PLAIN}  拥塞控制:${LIGHT_YELLOW}bbr${PLAIN}"
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
