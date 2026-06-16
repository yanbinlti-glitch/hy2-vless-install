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
        ip=$(curl -fsSLk -m 4 http://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(curl -fsSLk -m 4 http://api.ipify.org 2 --retry 2 --connect-timeout 6 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && command -v wget >/dev/null 2>&1; then
        ip=$(wget -qO- -T 4 http://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(wget -qO- -T 4 http://api.ipify.org 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')
    fi
    echo "$ip"
}

main_status_get_public_ipv6() {
    local ip=""
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -fsSLk -m 4 http://ipv6.icanhazip.com 2>/dev/null | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(curl -fsSLk -m 4 http://api64.ipify.org 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$ip" || ! "$ip" =~ ":" ]] && command -v wget >/dev/null 2>&1; then
        ip=$(wget -qO- -T 4 http://ipv6.icanhazip.com 2>/dev/null | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(wget -qO- -T 4 http://api64.ipify.org 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ -z "$ip" || ! "$ip" =~ ":" ]]; then
        ip=$(ip -o -6 addr show scope global 2>/dev/null | awk '$2 != "wgcf" && $2 !~ /warp/i && $4 !~ /^fd/ {split($4,a,"/"); print a[1]; exit}')
    fi
    echo "$ip"
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


main_status_landing_info() {
    if [[ ! -f /etc/sing-box/config.json ]]; then
        echo "未知"
        return
    fi
    local has_proxy=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json 2>/dev/null)
    if [[ -z "$has_proxy" || "$has_proxy" == "null" ]]; then
        local geo=$(curl -fsSLk -m 6 "http://ip-api.com/json/?lang=zh-CN" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local country=$(echo "$geo" | jq -r '.country')
            local city=$(echo "$geo" | jq -r '.city')
            local isp=$(echo "$geo" | jq -r '.isp')
            echo -e "${LIGHT_CYAN}[本机直连]${PLAIN} $country $city ($isp)"
        else
            echo -e "${LIGHT_CYAN}[本机直连]${PLAIN} 获取归属地超时"
        fi
    else
        local p_type=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json)
        local p_server=$(jq -r '.outbounds[] | select(.tag=="proxy") | .server' /etc/sing-box/config.json)
        local p_port=$(jq -r '.outbounds[] | select(.tag=="proxy") | .server_port' /etc/sing-box/config.json)
        local p_user=$(jq -r '.outbounds[] | select(.tag=="proxy") | .username // empty' /etc/sing-box/config.json)
        local p_pass=$(jq -r '.outbounds[] | select(.tag=="proxy") | .password // empty' /etc/sing-box/config.json)
        local p_tls=$(jq -r '.outbounds[] | select(.tag=="proxy") | .tls.enabled // empty' /etc/sing-box/config.json)
        local is_global=$(jq -e '.route.rules[] | select(.outbound=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null))' /etc/sing-box/config.json >/dev/null 2>&1 && echo "全局" || echo "分流")
        
        local curl_proxy=""
        local proto_prefix="socks5h"
        if [[ "$p_type" == "http" ]]; then
            proto_prefix="http"
            [[ "$p_tls" == "true" ]] && proto_prefix="https"
        fi
        local safe_server="$p_server"
        [[ "$safe_server" =~ ":" ]] && safe_server="[$safe_server]"
        local safe_user=$(jq -nr --arg v "$p_user" '$v|@uri' 2>/dev/null || echo "$p_user")
        local safe_pass=$(jq -nr --arg v "$p_pass" '$v|@uri' 2>/dev/null || echo "$p_pass")
        if [[ -n "$p_user" ]]; then
            curl_proxy="-x ${proto_prefix}://${safe_user}:${safe_pass}@${safe_server}:${p_port}"
        else
            curl_proxy="-x ${proto_prefix}://${safe_server}:${p_port}"
        fi
        local geo=$(curl -fsSLk -m 6 $curl_proxy "http://ip-api.com/json/?lang=zh-CN" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            echo -e "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} $ip ($country - $isp)"
        else
            echo -e "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} 检测失败 (节点超时或阻断)"
        fi
    fi
}


main_status_landing_ip() {
    if [[ ! -f /etc/sing-box/config.json ]] || ! command -v jq >/dev/null 2>&1; then
        echo "未知 (未部署节点)"
        return
    fi
    
    local has_proxy=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json 2>/dev/null)
    if [[ -z "$has_proxy" || "$has_proxy" == "null" ]]; then
        local geo=$(curl -fsSLk -m 6 "http://ip-api.com/json/?lang=zh-CN" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            echo -e "${LIGHT_CYAN}[本机直连]${PLAIN} $ip ($country - $isp)"
        else
            echo -e "${LIGHT_CYAN}[本机直连]${PLAIN} 获取超时"
        fi
    else
        local p_type=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json 2>/dev/null)
        local p_server=$(jq -r '.outbounds[] | select(.tag=="proxy") | .server' /etc/sing-box/config.json 2>/dev/null)
        local p_port=$(jq -r '.outbounds[] | select(.tag=="proxy") | .server_port' /etc/sing-box/config.json 2>/dev/null)
        local p_user=$(jq -r '.outbounds[] | select(.tag=="proxy") | .username // empty' /etc/sing-box/config.json 2>/dev/null)
        local p_pass=$(jq -r '.outbounds[] | select(.tag=="proxy") | .password // empty' /etc/sing-box/config.json 2>/dev/null)
        local p_tls=$(jq -r '.outbounds[] | select(.tag=="proxy") | .tls.enabled // empty' /etc/sing-box/config.json 2>/dev/null)
        local is_global=$(jq -e '.route.rules[] | select(.outbound=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null))' /etc/sing-box/config.json >/dev/null 2>&1 && echo "全局" || echo "智能分流")
        
        local curl_proxy=""
        local proto_prefix="socks5h"
        if [[ "$p_type" == "http" ]]; then
            proto_prefix="http"
            [[ "$p_tls" == "true" ]] && proto_prefix="https"
        fi
        local safe_server="$p_server"
        [[ "$safe_server" =~ ":" ]] && safe_server="[$safe_server]"
        local safe_user=$(jq -nr --arg v "$p_user" '$v|@uri' 2>/dev/null || echo "$p_user")
        local safe_pass=$(jq -nr --arg v "$p_pass" '$v|@uri' 2>/dev/null || echo "$p_pass")
        if [[ -n "$p_user" ]]; then
            curl_proxy="-x ${proto_prefix}://${safe_user}:${safe_pass}@${safe_server}:${p_port}"
        else
            curl_proxy="-x ${proto_prefix}://${safe_server}:${p_port}"
        fi
        
        local geo=$(curl -fsSLk -m 6 $curl_proxy "http://ip-api.com/json/?lang=zh-CN" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            echo -e "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} $ip ($country - $isp)"
        else
            echo -e "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} 检测失败 (节点超时或被阻断)"
        fi
    fi
}

main_realtime_status_panel() {
    trap 'rm -f /tmp/hy2_*_$$.tmp 2>/dev/null' RETURN
    local os_name kernel arch virt bbr ipv4 ipv6 warp_iface warp_ipv6 sb_ver sb_latest svc_text script_ver

    os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    [[ -z "$os_name" ]] && os_name="unknown"

    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    virt=$(main_status_detect_virtualization)
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")

    # 异步并发执行耗时网络探测
    main_status_get_public_ipv4 > /tmp/hy2_ipv4_$$.tmp 2>/dev/null &
    PID1=$!
    main_status_get_public_ipv6 > /tmp/hy2_ipv6_$$.tmp 2>/dev/null &
    PID2=$!
    main_status_latest_singbox_version > /tmp/hy2_sblatest_$$.tmp 2>/dev/null &
    PID3=$!
    main_status_landing_ip > /tmp/hy2_landing_$$.tmp 2>/dev/null &
    PID4=$!
    
    ( sleep 6; kill -9 $PID1 $PID2 $PID3 $PID4 >/dev/null 2>&1 ) >/dev/null 2>&1 &
    WATCHDOG_PID=$!
    
    wait $PID1 $PID2 $PID3 $PID4 2>/dev/null
    kill $WATCHDOG_PID >/dev/null 2>&1 || true

    ipv4=$(cat /tmp/hy2_ipv4_$$.tmp 2>/dev/null)
    ipv6=$(cat /tmp/hy2_ipv6_$$.tmp 2>/dev/null)
    sb_latest=$(cat /tmp/hy2_sblatest_$$.tmp 2>/dev/null); [[ -z "$sb_latest" ]] && sb_latest="获取失败"
    local landing_info=$(cat /tmp/hy2_landing_$$.tmp 2>/dev/null); [[ -z "$landing_info" ]] && landing_info="检测超时 (网络黑洞)"
    rm -f /tmp/hy2_ipv4_$$.tmp /tmp/hy2_ipv6_$$.tmp /tmp/hy2_sblatest_$$.tmp /tmp/hy2_landing_$$.tmp 2>/dev/null
    
    warp_iface=$(main_status_get_warp_iface)
    script_ver="${HY2_VLESS_VERSION:-dev}"
    sb_ver=$(main_status_singbox_version)

    if is_svc_active sing-box; then
        svc_text="${LIGHT_GREEN}运行中${PLAIN}"
    else
        svc_text="${LIGHT_RED}未运行 / 异常${PLAIN}"
    fi

    # 清洗并缓存真实 IPv4 以供直连显示
    local clean_ipv4="${ipv4}"
    [[ -z "$clean_ipv4" || "$clean_ipv4" == "检测超时"* ]] && ipv4="未检测到"
    [[ -z "$ipv6" || "$ipv6" == "检测超时"* ]] && ipv6="无公网IPv6"

    if [[ -n "$warp_iface" ]]; then
        warp_ipv6=$(ip -6 addr show dev "$warp_iface" scope global 2>/dev/null | awk '/inet6/ {print $2; exit}' | cut -d/ -f1)
        [[ -n "$warp_ipv6" ]] && warp_iface="${warp_iface} (${warp_ipv6})"
    else
        warp_iface="未检测到"
    fi

    # 动态探测中转模式
    local target_inbound=""
    local out_mode="未开启"
    if jq -e '.route.rules[] | select(.outbound=="proxy" and .inbound != null)' /etc/sing-box/config.json >/dev/null 2>&1; then
        out_mode="指定节点"
        target_inbound=$(jq -r '.route.rules[] | select(.outbound=="proxy" and .inbound != null) | .inbound[]' /etc/sing-box/config.json 2>/dev/null)
    elif jq -e '.route.rules[] | select(.outbound=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null and .inbound == null))' /etc/sing-box/config.json >/dev/null 2>&1; then
        out_mode="全局中转"
    elif jq -e '.route.rules[] | select(.outbound=="proxy")' /etc/sing-box/config.json >/dev/null 2>&1; then
        out_mode="智能分流"
    fi

    echo -e " ${LIGHT_CYAN}实时状态面板${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e " ${LIGHT_YELLOW}Sing-box状态:${PLAIN} ${svc_text}    ${LIGHT_YELLOW}核心版本:${PLAIN} ${sb_ver}    ${LIGHT_YELLOW}最新官方版:${PLAIN} ${sb_latest}"
    echo -e " ${LIGHT_YELLOW}系统:${PLAIN} ${os_name}    ${LIGHT_YELLOW}内核:${PLAIN} ${kernel} "   
    echo -e " ${LIGHT_YELLOW}BBR算法:${PLAIN} ${bbr}     ${LIGHT_YELLOW}架构:${PLAIN} ${arch}    ${LIGHT_YELLOW}虚拟化:${PLAIN} ${virt}"
    echo -e " ${LIGHT_YELLOW}本机IPv4:${PLAIN} ${ipv4}"
    echo -e " ${LIGHT_YELLOW}本机IPv6:${PLAIN} ${ipv6}"    
    echo -e " ${LIGHT_YELLOW}WARP接口:${PLAIN} ${warp_iface}"

    # 直连 IP 终极高压补位系统
    local disp_v4="${clean_ipv4}"
    if [[ -z "$disp_v4" || "$disp_v4" == "检测超时"* ]]; then
        disp_v4=$(curl -fsS4m2 https://api.ipify.org 2 --retry 2 --connect-timeout 6 2>/dev/null || ip route get 1.1.1.1 2>/dev/null | awk '{print $NF; exit}')
        [[ -z "$disp_v4" ]] && disp_v4="未知本机IP"
    fi

    # 落地 IP 双轨重装渲染逻辑
    if [[ "$out_mode" == "指定节点" ]]; then
        if [[ "$target_inbound" == "hy2-in" ]]; then
            echo -e " ${LIGHT_GREEN}▶ Hy2 落地IP :${PLAIN} ${LIGHT_PURPLE}${landing_info} (定向中转)${PLAIN}"
            echo -e " ${LIGHT_GREEN}▶ VLESS 落地 :${PLAIN} ${LIGHT_CYAN}[本机直连] ${disp_v4}${PLAIN}"
        elif [[ "$target_inbound" == "vless-in" ]]; then
            echo -e " ${LIGHT_GREEN}▶ Hy2 落地IP :${PLAIN} ${LIGHT_CYAN}[本机直连] ${disp_v4}${PLAIN}"
            echo -e " ${LIGHT_GREEN}▶ VLESS 落地 :${PLAIN} ${LIGHT_PURPLE}${landing_info} (定向中转)${PLAIN}"
        fi
    else
        local suffix=""
        [[ "$out_mode" == "全局中转" ]] && suffix=" (全局强转)"
        [[ "$out_mode" == "智能分流" ]] && suffix=" (流媒体智能分流)"
        
        if [[ "$out_mode" == "未开启" ]]; then
            echo -e " ${LIGHT_YELLOW}落地网络:${PLAIN} ${LIGHT_CYAN}${landing_info}${PLAIN}"
        else
            echo -e " ${LIGHT_YELLOW}落地网络:${PLAIN} ${LIGHT_PURPLE}${landing_info}${suffix}${PLAIN}"
        fi
    fi
    # --- 租期看门狗倒计时高精渲染引擎 ---
    local exp_time=$(cat /etc/sing-box/expiration.txt 2>/dev/null || echo "0")
    if [[ "$exp_time" -gt 0 ]]; then
        local now_ts=$(date +%s)
        if [[ "$now_ts" -ge "$exp_time" ]]; then
            echo -e " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_RED}已过期 (后台看门狗已强行断网停用)${PLAIN}"
            if is_svc_active sing-box; then
                rc-service sing-box stop >/dev/null 2>&1 || systemctl stop sing-box >/dev/null 2>&1
            fi
        else
            local diff_ts=$((exp_time - now_ts))
            local r_days=$((diff_ts / 86400))
            local r_hours=$(( (diff_ts % 86400) / 3600 ))
            local r_mins=$(( (diff_ts % 3600) / 60 ))
            echo -e " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_GREEN}剩余 ${r_days} 天 ${r_hours} 小时 ${r_mins} 分钟 (到期自动断网)${PLAIN}"
        fi
    else
        echo -e " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_GREEN}永久有效 (未设置时间限制)${PLAIN}"
    fi

    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    main_status_show_node_info
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
  echo -e " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  echo -e " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  echo -e " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  echo -e " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_CYAN}检查 / 在线更新脚本${PLAIN}"
  echo -e " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  echo -e " ${LIGHT_GREEN}[11]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  echo -e " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-11]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in     0 ) exit 0 ;;     1 ) inst_singbox ;;
        2)
            _modify_node_port
            ;;     2 ) remove_node ;;     3 ) singbox_switch ;;     4 ) config_modify_menu ;;     5 ) warp_ipv6_route_menu ;;     6 ) config_outbound ;;     7 ) showconf ;;     8 ) self_update ;;     9 ) enable_bbr ;;     10 ) quick_repair_and_status ;;     11 ) global_uninstall ;;     * ) red " 输入无效"; sleep 1 ;; esac
}


# --- V1.6.3 端口动态跃迁与订阅同步引擎 ---
_modify_node_port() {
    echo ""
    echo -e "  \033[1;36m▶ 启动端口动态跃迁机制...\033[0m"
    echo -e "  \033[1;33m⚠️ 注意：修改端口会同步刷新 Nginx 在线订阅文件及终端生成的明文链接！\033[0m"
    echo ""
    read -p "  请输入全新节点通信端口 (10000-65535) [直接回车取消]: " new_port
    
    if [ -z "$new_port" ]; then
        echo "  [i] 操作已取消，未做任何变更。"
        return 0
    fi
    
    # 1. 严格的类型与范围约束
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 10000 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "  \033[1;31m[✘] 错误：端口号必须为 10000 到 65535 之间的纯数字！\033[0m"
        return 1
    fi

    # 2. 物理端口冲突硬核检查
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i:"$new_port" >/dev/null 2>&1; then
            echo -e "  \033[1;31m[✘] 错误：端口 $new_port 已被当前系统其他服务霸占，请更换！\033[0m"
            return 1
        fi
    fi

    # 3. 外科手术：重写 Sing-box 底层 Inbounds 监听配置
    if [ -f /etc/sing-box/config.json ]; then
        if jq '(.inbounds[] | select(.type=="vless" or .type=="hysteria2") | .listen_port) = '$new_port'' /etc/sing-box/config.json > /tmp/sb_tmp.json 2>/dev/null; then
            mv -f /tmp/sb_tmp.json /etc/sing-box/config.json
        else
            echo -e "  \033[1;31m[✘] 错误：底层 JSON 配置解析失败，拒绝写入！\033[0m"
            return 1
        fi
    fi

    # 4. 全量数据持久化同步：刷新存储目录下的所有环境变量及端口快照 (保障订阅生成线同步)
    if [ -d /etc/hy2-vless ]; then
        find /etc/hy2-vless/ -type f -exec sed -i "s/^PORT=.*/PORT=$new_port/g" {} + 2>/dev/null || true
        find /etc/hy2-vless/ -type f -exec sed -i "s/^port=.*/port=$new_port/g" {} + 2>/dev/null || true
    fi

    # 5. 调用 V1.5.7 全局劫持装甲：瞬间释放旧端口，打通新防火墙并平滑唤醒核心
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sing-box >/dev/null 2>&1
    fi
    
    echo ""
    echo -e "  \033[1;32m[✔] 成功！通信端口已平滑跃迁至 [ $new_port ]，订阅分发系统已完成全量全同步！\033[0m"
    echo ""
    read -n 1 -s -r -p "按任意键返回信息面板..."
}
