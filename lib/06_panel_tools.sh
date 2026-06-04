#!/usr/bin/env bash
# shellcheck shell=bash

#  7. 二级管控面板与辅助工具
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
            if [[ $has_vless -eq 0 ]]; then
                yellow "  [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
                clean_env "keep_core"
                green "  [✔] Hysteria 2 节点及关联服务已成功卸载！(核心已保留)"
            else
                close_port_by_tag "hy2-in"
                jq 'del(.inbounds[] | select(.tag=="hy2-in"))' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
                generate_client_configs
                restart_singbox_checked
                green "  [✔] Hysteria 2 节点已成功卸载！"
            fi
            sleep 2
            ;;
        2)
            [[ $has_vless -eq 0 ]] && return
            if [[ $has_hy2 -eq 0 ]]; then
                yellow "  [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
                clean_env "keep_core"
                green "  [✔] VLESS 节点及关联服务已成功卸载！(核心已保留)"
            else
                close_port_by_tag "vless-in"
                jq 'del(.inbounds[] | select(.tag=="vless-in"))' /etc/sing-box/config.json > /tmp/sb.json && mv /tmp/sb.json /etc/sing-box/config.json
                generate_client_configs
                restart_singbox_checked
                green "  [✔] VLESS 节点已成功卸载！"
            fi
            sleep 2
            ;;
        3)
            clean_env "keep_core"
            green "  [✔] 所有节点配置、订阅及防火墙规则已被彻底清理！(核心已保留)"
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
            restart_singbox_checked
            sleep 1
            if is_svc_active sing-box; then
                green "  [✔] 重启成功！新配置已生效。"
                generate_client_configs
            else
                red "  [✘] 核心拒绝启动！已恢复修改前的配置。"
                mv /tmp/config.json.bak /etc/sing-box/config.json
                svc_stop sing-box
                svc_start sing-box
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
              .route.rules = [{"domain_suffix": ["netflix.com", "nflxvideo.net", "openai.com", "chatgpt.com", "disneyplus.com"], "action": "route", "outbound": "proxy"}] + .route.rules
            ' /etc/sing-box/config.json > /tmp/sb_out.json
            mv /tmp/sb_out.json /etc/sing-box/config.json
            
            green "  新落地代理配置写入完毕！"
            restart_singbox_checked
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
            
            restart_singbox_checked
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

ensure_subscription_ready() {
    # 进入“查看订阅”前强制重建一次，防止 sub_path.txt 或 url.txt 丢失导致链接变成 http://IP:端口/
    normalize_singbox_config || true
    generate_client_configs

    local sub_path=$(cat /etc/sing-box/sub_path.txt 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9')
    local sub_port=$(cat /etc/sing-box/sub_port.txt 2>/dev/null | LC_ALL=C tr -dc '0-9')

    if [[ -z "$sub_port" || -z "$sub_path" || ! -s "/var/www/sing-box/$sub_path/url.txt" ]]; then
        check_installed_nodes
        echo ""
        red "  [错误] 订阅信息未能生成完整。"
        yellow "  当前检测到的节点状态: Hysteria2=$has_hy2 / VLESS=$has_vless"
        yellow "  这通常说明 /etc/sing-box/config.json 里没有 hy2-in 或 vless-in 入站，或节点配置未通过校验。"
        echo ""
        yellow "  请在服务器执行下面三条，把输出发给我："
        echo -e "${LIGHT_GREEN}    /usr/local/bin/sing-box check -c /etc/sing-box/config.json${PLAIN}"
        echo -e "${LIGHT_GREEN}    jq '.inbounds[]?.tag' /etc/sing-box/config.json${PLAIN}"
        if [[ $SYSTEM == "Alpine" ]]; then
            echo -e "${LIGHT_GREEN}    tail -n 80 /var/log/sing-box.log${PLAIN}"
        else
            echo -e "${LIGHT_GREEN}    journalctl -u sing-box -n 80 --no-pager${PLAIN}"
        fi
        return 1
    fi
    return 0
}

showconf() {
    clear
    echo ""
    yellow "  正在刷新订阅与直连节点信息..."
    if ! ensure_subscription_ready; then
        echo ""
        echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
        read temp
        return
    fi

    realip
    local sub_port=$(cat /etc/sing-box/sub_port.txt 2>/dev/null | LC_ALL=C tr -dc '0-9')
    local sub_path=$(cat /etc/sing-box/sub_path.txt 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9')
    local sub_url="http://${PUBLIC_IP}:${sub_port}/${sub_path}"
    [[ "$PUBLIC_IP" == *":"* ]] && sub_url="http://[${PUBLIC_IP}]:${sub_port}/${sub_path}"

    local raw_url=$(cat "/var/www/sing-box/$sub_path/url.txt" 2>/dev/null)

    clear
    echo ""
    print_line
    green "               Sing-box 节点配置与全平台智能订阅           "
    print_line
    echo ""
    yellow "  ▶ [多核聚合智能订阅链接] (HTTP 极速分发版)"
    purple "    适用客户端: Sing-box / Clash Verge / v2rayN 等"
    green  "    订阅地址: ${sub_url}"
    green  "    二维码图片: ${sub_url}/sub_qr.png"
    echo ""
    yellow "  ▶ [订阅二维码]"
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t ANSIUTF8 "$sub_url" || yellow "    二维码渲染失败，请直接复制订阅地址。"
    elif [[ -f "/var/www/sing-box/$sub_path/sub_qr.txt" ]]; then
        cat "/var/www/sing-box/$sub_path/sub_qr.txt"
    else
        yellow "    未检测到 qrencode，请重新运行安装流程补齐二维码组件。"
    fi
    echo ""
    yellow "  ▶ [单节点直连链接]"
    purple "    适用客户端: NekoBox / v2rayNG (直接导入)"
    green  "    节点地址:"
    echo -e "${LIGHT_GREEN}${raw_url}${PLAIN}"
    echo ""

    print_line
    yellow "  ▶ 自助排障与安全特性提醒 (必读)："
    echo -e "    ${LIGHT_GREEN}如果订阅链接无法打开，请先确认 VPS 安全组已放行 TCP 订阅端口 ${sub_port}。${PLAIN}"
    echo -e "    ${LIGHT_GREEN}如果 Hy2 节点无法连接，请确认 VPS 安全组已放行对应 UDP 主端口。${PLAIN}"
    echo -e "    ${LIGHT_GREEN}Hy2 与 VLESS 已在安装时写入推荐协议参数；若要提升 UDP/TCP 链路表现，可在菜单 [7] 开启 BBR/缓冲区优化。${PLAIN}"
    echo -e "    ${LIGHT_PURPLE}====================================================${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

enable_bbr() {
    echo ""
    print_line
    green "             BBR / TCP Fast Open / Hy2 UDP / VLESS TCP 加速参数             "
    print_line
    echo ""

    local kernel_v=$(uname -r | cut -d. -f1)
    if [[ "$kernel_v" -lt 4 ]]; then
        red "  当前内核版本过低 ($(uname -r))，不支持开启 BBR！"
        sleep 3; return
    fi

    yellow "  正在检测 BBR 模块与拥塞控制支持，完整输出如下："
    modprobe tcp_bbr || true
    echo "  可用拥塞控制: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo unknown)"
    if ! grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        red "  [错误] 当前系统/内核 (可能是 LXC 容器) 不支持 BBR 模块！"
        sleep 3; return
    fi
    
    local total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    [[ -z "$total_mem_kb" ]] && total_mem_kb=1048576
    local page_size=$(getconf PAGESIZE 2>/dev/null || echo 4096)
    if ! [[ "$page_size" =~ ^[0-9]+$ ]] || [[ "$page_size" -le 0 ]]; then
        page_size=4096
    fi
    local mem_pages=$(( total_mem_kb / (page_size / 1024) ))
    local udp_max=$(( mem_pages / 4 ))
    [[ $udp_max -lt 65536 ]] && udp_max=65536
    local udp_mid=$(( udp_max * 3 / 4 ))
    local udp_min=$(( udp_max / 2 ))

    local current_file_max=$(sysctl -n fs.file-max 2>/dev/null || echo 0)
    local file_max_config=""
    if [[ "$current_file_max" -lt 1048576 ]]; then
        file_max_config="fs.file-max=1048576
fs.nr_open=1048576"
    fi

    mkdir -p /etc/sysctl.d
    cp -a /etc/sysctl.d/99-singbox-bbr.conf "/etc/sysctl.d/99-singbox-bbr.conf.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
    cat << EOF > /etc/sysctl.d/99-singbox-bbr.conf
$file_max_config
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_local_port_range=1024 65535
net.core.rmem_max=67108864
net.core.rmem_default=26214400
net.core.wmem_max=67108864
net.core.wmem_default=26214400
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.udp_mem=$udp_min $udp_mid $udp_max
EOF
    
    yellow "  正在应用 sysctl 参数，完整输出如下："
    sysctl -e -p /etc/sysctl.d/99-singbox-bbr.conf
    echo ""
    yellow "  当前关键参数："
    sysctl net.ipv4.tcp_congestion_control || true
    sysctl net.core.default_qdisc || true
    sysctl net.ipv4.tcp_fastopen || true
    sysctl net.ipv4.tcp_mtu_probing || true
    sysctl net.core.rmem_max || true
    sysctl net.core.wmem_max || true

    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo ""
        green "  [✔] BBR + TCP Fast Open + Hy2 UDP / VLESS TCP 缓冲区参数已应用。"
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
        1 ) restart_singbox_checked && green "  Sing-box 核心已启动/重载！"; sleep 2 ;;
        2 ) svc_stop sing-box; yellow "  Sing-box 核心已停止！"; sleep 2 ;;
        3 ) restart_singbox_checked && { if is_svc_active nginx; then if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx restart; else systemctl restart nginx; fi; fi; green "  核心服务已校验并重启！"; }; sleep 2 ;;
        0 ) return ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

quick_repair_and_status() {
    clear
    echo ""
    print_line
    green "                 一键兼容修复与状态诊断                 "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red "  未检测到 /etc/sing-box/config.json，请先安装节点。"
        sleep 2
        return
    fi

    ensure_singbox_core || { echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回... ${PLAIN}"; read temp; return; }
    normalize_singbox_config
    echo ""
    yellow "  正在执行 sing-box 配置校验..."
    if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
        red "  [✘] 配置仍未通过，请复制上面的错误发给我。"
        echo ""
        echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回... ${PLAIN}"
        read temp
        return
    fi
    green "  [✔] 配置校验通过。"

    svc_enable sing-box
    restart_singbox_checked
    sleep 1
    if is_svc_active sing-box; then
        green "  [✔] sing-box 当前运行中。"
    else
        red "  [✘] sing-box 未运行。最近日志："
        if [[ $SYSTEM == "Alpine" ]]; then
            tail -n 80 /var/log/sing-box.log 2>/dev/null || true
        else
            journalctl -u sing-box -n 80 --no-pager 2>/dev/null || true
        fi
    fi

    generate_client_configs
    local diag_sub_path=$(cat /etc/sing-box/sub_path.txt 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9')
    if [[ -z "$diag_sub_path" || ! -s "/var/www/sing-box/$diag_sub_path/url.txt" ]]; then
        red "  [✘] 节点文件仍未生成：请检查配置中是否存在 hy2-in 或 vless-in 入站。"
        jq '.inbounds[]?.tag' /etc/sing-box/config.json 2>/dev/null || true
    else
        green "  [✔] 订阅路径与直连节点已生成: /$diag_sub_path"
    fi

    if nginx -t; then
        svc_enable nginx
        if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx restart; else systemctl restart nginx; fi
        green "  [✔] Nginx 订阅服务已重启。"
    else
        red "  [✘] Nginx 配置测试失败，请检查订阅端口是否被占用。"
    fi

    echo ""
    yellow "  监听端口："
    ss -lntup 2>/dev/null | grep -E 'sing-box|nginx' || true
    echo ""
    yellow "  订阅与节点信息可在主菜单 [6] 查看。"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

config_modify_menu() {
    while true; do
        clear
        print_line
        green " 查看 / 修改 配置文件 "
        print_line
        echo ""
        echo -e " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}修改配置文件${PLAIN}"
        echo ""
        echo -e " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
        echo ""
        echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-1]: ${PLAIN}"
        read config_modify_choice || return

        case "$config_modify_choice" in
            1) edit_config ;;
            0) return ;;
            *) red " 输入无效"; sleep 1 ;;
        esac
    done
}

