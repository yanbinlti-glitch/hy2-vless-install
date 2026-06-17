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

    printf "%b
" " ${LIGHT_CYAN}Sing-box 节点安装信息:${PLAIN}"

    if [[ -n "$vless_port" && "$vless_port" != "null" ]]; then
        vless_sni=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config.json 2>/dev/null)
        vless_flow=$(jq -r '.inbounds[]? | select(.tag=="vless-in") | .users[0].flow // empty' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$vless_sni" || "$vless_sni" == "null" ]] && vless_sni="未读取"
        [[ -z "$vless_flow" || "$vless_flow" == "null" ]] && vless_flow="xtls-rprx-vision"

        printf "%b
" " ${LIGHT_GREEN} ✔ [ VLESS-Reality ]${PLAIN} 端口:${LIGHT_YELLOW}${vless_port}${PLAIN}  Reality域名:${LIGHT_YELLOW}${vless_sni}${PLAIN}  flow:${LIGHT_YELLOW}${vless_flow}${PLAIN}"
    fi

    if [[ -n "$hy2_port" && "$hy2_port" != "null" ]]; then
        hy2_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "未读取")
        hy2_hop=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')
        [[ -z "$hy2_hop" ]] && hy2_hop="未开启"

        printf "%b
" " ${LIGHT_GREEN} ✔ [ Hysteria-2   ]${PLAIN} 端口:${LIGHT_YELLOW}${hy2_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${hy2_sni}${PLAIN}  跳跃端口:${LIGHT_YELLOW}${hy2_hop}${PLAIN}"
    fi
}


_menu_fetch_geo() {
  local proxy_url="${1-}"
  local response=""
  local -a curl_args=(
    --fail
    --silent
    --show-error
    --location
    --proto '=https'
    --tlsv1.2
    --connect-timeout 4
    --max-time 8
    --retry 1
  )

  command -v curl >/dev/null 2>&1 ||
    return 1

  command -v jq >/dev/null 2>&1 ||
    return 1

  if [[ -n "$proxy_url" ]]; then
    curl_args+=(
      --proxy
      "$proxy_url"
    )
  fi

  response=$(
    curl \
      "${curl_args[@]}" \
      "https://ipwho.is/?lang=zh-CN" \
      2>/dev/null
  ) || return 1

  # 转成旧显示代码使用的字段结构。
  jq -ce '
    if .success == true
       and (.ip | type == "string")
    then
      {
        status: "success",
        query: .ip,
        country: (.country // ""),
        city: (.city // ""),
        isp: (
          .connection.isp
          // .isp
          // ""
        )
      }
    else
      empty
    end
  ' <<< "$response"
}

main_status_landing_info() {
    if [[ ! -f /etc/sing-box/config.json ]]; then
        echo "未知"
        return
    fi
    local has_proxy=$(jq -r '.outbounds[] | select(.tag=="proxy") | .type' /etc/sing-box/config.json 2>/dev/null)
    if [[ -z "$has_proxy" || "$has_proxy" == "null" ]]; then
        local geo=$(_menu_fetch_geo 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local country=$(echo "$geo" | jq -r '.country')
            local city=$(echo "$geo" | jq -r '.city')
            local isp=$(echo "$geo" | jq -r '.isp')
            printf "%b
" "${LIGHT_CYAN}[本机直连]${PLAIN} $country $city ($isp)"
        else
            printf "%b
" "${LIGHT_CYAN}[本机直连]${PLAIN} 获取归属地超时"
        fi
    else
        eval "$(jq -r '.outbounds[] | select(.tag=="proxy") | @sh "local p_type=\(.type) p_server=\(.server) p_port=\(.server_port) p_user=\(.username // \"\") p_pass=\(.password // \"\") p_tls=\(.tls.enabled // \"\")"' /etc/sing-box/config.json 2>/dev/null)" 
        local is_global=$(jq -e '.route.rules[] | select(.outbound=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null))' /etc/sing-box/config.json >/dev/null 2>&1 && echo "全局" || echo "分流")
        
        local proxy_url=""
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
            proxy_url="${proto_prefix}://${safe_user}:${safe_pass}@${safe_server}:${p_port}"
        else
            proxy_url="${proto_prefix}://${safe_server}:${p_port}"
        fi
        local geo=$(_menu_fetch_geo "$proxy_url" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            printf "%b
" "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} $ip ($country - $isp)"
        else
            printf "%b
" "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} 检测失败 (节点超时或阻断)"
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
        local geo=$(_menu_fetch_geo 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            printf "%b
" "${LIGHT_CYAN}[本机直连]${PLAIN} $ip ($country - $isp)"
        else
            printf "%b
" "${LIGHT_CYAN}[本机直连]${PLAIN} 获取超时"
        fi
    else
        eval "$(jq -r '.outbounds[] | select(.tag=="proxy") | @sh "local p_type=\(.type) p_server=\(.server) p_port=\(.server_port) p_user=\(.username // \"\") p_pass=\(.password // \"\") p_tls=\(.tls.enabled // \"\")"' /etc/sing-box/config.json 2>/dev/null)" 
        local is_global=$(jq -e '.route.rules[] | select(.outbound=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null))' /etc/sing-box/config.json >/dev/null 2>&1 && echo "全局" || echo "智能分流")
        
        local proxy_url=""
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
            proxy_url="${proto_prefix}://${safe_user}:${safe_pass}@${safe_server}:${p_port}"
        else
            proxy_url="${proto_prefix}://${safe_server}:${p_port}"
        fi
        
        local geo=$(_menu_fetch_geo "$proxy_url" 2>/dev/null)
        local status=$(echo "$geo" | jq -r '.status' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            local ip=$(echo "$geo" | jq -r '.query')
            local country=$(echo "$geo" | jq -r '.country')
            local isp=$(echo "$geo" | jq -r '.isp')
            printf "%b
" "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} $ip ($country - $isp)"
        else
            printf "%b
" "${LIGHT_PURPLE}[${is_global}中转]${PLAIN} 检测失败 (节点超时或被阻断)"
        fi
    fi
}

main_realtime_status_panel() {
    local status_tmp_dir=""

  status_tmp_dir=$(
    mktemp -d \
      "${TMPDIR:-/tmp}/hy2-status.XXXXXX"
  ) || {
    red " [错误] 无法创建状态面板私有临时目录。"
    return 1
  }

  chmod 700 "$status_tmp_dir" || {
    rm -rf -- "$status_tmp_dir"
    return 1
  }

  trap 'rm -rf -- "$status_tmp_dir"' RETURN
    local os_name kernel arch virt bbr ipv4 ipv6 warp_iface warp_ipv6 sb_ver sb_latest svc_text script_ver

    os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    [[ -z "$os_name" ]] && os_name="unknown"

    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    virt=$(main_status_detect_virtualization)
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")

    # 异步并发执行耗时网络探测
    main_status_get_public_ipv4 > "$status_tmp_dir/ipv4" 2>/dev/null &
    PID1=$!
    main_status_get_public_ipv6 > "$status_tmp_dir/ipv6" 2>/dev/null &
    PID2=$!
    main_status_latest_singbox_version > "$status_tmp_dir/sblatest" 2>/dev/null &
    PID3=$!
    main_status_landing_ip > "$status_tmp_dir/landing" 2>/dev/null &
    PID4=$!
    
    ( sleep 6; kill -9 $PID1 $PID2 $PID3 $PID4 >/dev/null 2>&1 ) >/dev/null 2>&1 &
    WATCHDOG_PID=$!
    
    wait $PID1 $PID2 $PID3 $PID4 2>/dev/null
    kill $WATCHDOG_PID >/dev/null 2>&1 || true

    ipv4=$(cat "$status_tmp_dir/ipv4" 2>/dev/null)
    ipv6=$(cat "$status_tmp_dir/ipv6" 2>/dev/null)
    sb_latest=$(cat "$status_tmp_dir/sblatest" 2>/dev/null); [[ -z "$sb_latest" ]] && sb_latest="获取失败"
    local landing_info=$(cat "$status_tmp_dir/landing" 2>/dev/null); [[ -z "$landing_info" ]] && landing_info="检测超时 (网络黑洞)"
    # 私有临时目录由 RETURN trap 统一删除。
    
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

    printf "%b
" " ${LIGHT_CYAN}实时状态面板${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    printf "%b
" " ${LIGHT_YELLOW}Sing-box状态:${PLAIN} ${svc_text}    ${LIGHT_YELLOW}核心版本:${PLAIN} ${sb_ver}    ${LIGHT_YELLOW}最新官方版:${PLAIN} ${sb_latest}"
    printf "%b
" " ${LIGHT_YELLOW}系统:${PLAIN} ${os_name}    ${LIGHT_YELLOW}内核:${PLAIN} ${kernel} "   
    printf "%b
" " ${LIGHT_YELLOW}BBR算法:${PLAIN} ${bbr}     ${LIGHT_YELLOW}架构:${PLAIN} ${arch}    ${LIGHT_YELLOW}虚拟化:${PLAIN} ${virt}"
    printf "%b
" " ${LIGHT_YELLOW}本机IPv4:${PLAIN} ${ipv4}"
    printf "%b
" " ${LIGHT_YELLOW}本机IPv6:${PLAIN} ${ipv6}"    
    printf "%b
" " ${LIGHT_YELLOW}WARP接口:${PLAIN} ${warp_iface}"

    # 直连 IP 终极高压补位系统
    local disp_v4="${clean_ipv4}"
    if [[ -z "$disp_v4" || "$disp_v4" == "检测超时"* ]]; then
        disp_v4=$(curl --fail --silent --show-error --location --ipv4 --proto '=https' --tlsv1.2 --max-time 4 --retry 2 --connect-timeout 3 https://api.ipify.org 2>/dev/null || ip route get 1.1.1.1 2>/dev/null | awk '{print $NF; exit}')
        [[ -z "$disp_v4" ]] && disp_v4="未知本机IP"
    fi

    # 落地 IP 双轨重装渲染逻辑
    if [[ "$out_mode" == "指定节点" ]]; then
        if [[ "$target_inbound" == "hy2-in" ]]; then
            printf "%b
" " ${LIGHT_GREEN}▶ Hy2 落地IP :${PLAIN} ${LIGHT_PURPLE}${landing_info} (定向中转)${PLAIN}"
            printf "%b
" " ${LIGHT_GREEN}▶ VLESS 落地 :${PLAIN} ${LIGHT_CYAN}[本机直连] ${disp_v4}${PLAIN}"
        elif [[ "$target_inbound" == "vless-in" ]]; then
            printf "%b
" " ${LIGHT_GREEN}▶ Hy2 落地IP :${PLAIN} ${LIGHT_CYAN}[本机直连] ${disp_v4}${PLAIN}"
            printf "%b
" " ${LIGHT_GREEN}▶ VLESS 落地 :${PLAIN} ${LIGHT_PURPLE}${landing_info} (定向中转)${PLAIN}"
        fi
    else
        local suffix=""
        [[ "$out_mode" == "全局中转" ]] && suffix=" (全局强转)"
        [[ "$out_mode" == "智能分流" ]] && suffix=" (流媒体智能分流)"
        
        if [[ "$out_mode" == "未开启" ]]; then
            printf "%b
" " ${LIGHT_YELLOW}落地网络:${PLAIN} ${LIGHT_CYAN}${landing_info}${PLAIN}"
        else
            printf "%b
" " ${LIGHT_YELLOW}落地网络:${PLAIN} ${LIGHT_PURPLE}${landing_info}${suffix}${PLAIN}"
        fi
    fi
    # --- 租期看门狗倒计时高精渲染引擎 ---
    local exp_time=$(cat /etc/sing-box/expiration.txt 2>/dev/null || echo "0")
    if [[ "$exp_time" -gt 0 ]]; then
        local now_ts=$(date +%s)
        if [[ "$now_ts" -ge "$exp_time" ]]; then
            printf "%b
" " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_RED}已过期 (后台看门狗已强行断网停用)${PLAIN}"
            if is_svc_active sing-box; then
                rc-service sing-box stop >/dev/null 2>&1 || systemctl stop sing-box >/dev/null 2>&1
            fi
        else
            local diff_ts=$((exp_time - now_ts))
            local r_days=$((diff_ts / 86400))
            local r_hours=$(( (diff_ts % 86400) / 3600 ))
            local r_mins=$(( (diff_ts % 3600) / 60 ))
            printf "%b
" " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_GREEN}剩余 ${r_days} 天 ${r_hours} 小时 ${r_mins} 分钟 (到期自动断网)${PLAIN}"
        fi
    else
        printf "%b
" " ${LIGHT_YELLOW}▶ 节点有效期:${PLAIN} ${LIGHT_GREEN}永久有效 (未设置时间限制)${PLAIN}"
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
  printf "%b
" "${LIGHT_GREEN}  ██████╗  ██╗   ██╗ ██████╗  ██╗       █████╗ ${PLAIN}"
  printf "%b
" "${LIGHT_GREEN}  ██╔══██╗ ██║   ██║ ██╔═══██╗██║      ██╔══██╗${PLAIN}"
  printf "%b
" "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ███████║${PLAIN}"
  printf "%b
" "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ██╔══██║${PLAIN}"
  printf "%b
" "${LIGHT_GREEN}  ██████╔╝ ╚██████╔╝ ╚██████╔╝███████╗ ██║  ██║${PLAIN}"
  printf "%b
" "${LIGHT_GREEN}  ╚═════╝   ╚══════╝  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝  ${LIGHT_YELLOW}[当前状态: ${status_ui}${LIGHT_YELLOW}]${PLAIN}"
  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
   printf "%b
" " ${LIGHT_YELLOW}当前版本 ：v${version_ui}${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}项目名称 ：Sing-box (Hy2 / VLESS) 一键部署与管理脚本 (Nginx订阅加强版)${PLAIN}"
  printf "%b
" " ${LIGHT_PURPLE}项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch${PLAIN}"
  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  main_realtime_status_panel
    yellow " 脚本快捷方式：666 (已自动配置，下次可在终端直接输入 666 启动)"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

  printf "%b
" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 节点核心 (Hysteria 2 / VLESS)${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b
" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b
" " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_CYAN}检查 / 在线更新脚本${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  printf "%b
" " ${LIGHT_GREEN}[11]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b
" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-11]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in     0 ) exit 0 ;;     1 ) inst_singbox ;;
        2 ) remove_node ;;     3 ) singbox_switch ;;     4 ) config_modify_menu ;;     5 ) warp_ipv6_route_menu ;;     6 ) config_outbound ;;     7 ) showconf ;;     8 ) self_update ;;     9 ) enable_bbr ;;     10 ) quick_repair_and_status ;;     11 ) global_uninstall ;;     * ) red " 输入无效"; sleep 1 ;; esac
}


