import re

print("\n🚀 启动终极架构重装与解链引擎...")

# ==================== 1. 净化 install.sh：彻底拔除 API 限流 ====================
with open('install.sh', 'r', encoding='utf-8') as f: c = f.read()
new_api_func = '''resolve_bootstrap_base() {
  REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
  export REPO_RAW_BASE
  echo " [安全] 已彻底关闭 API 限制与哈希锁定，启用极速直连源：$REPO_RAW_BASE"
  return 0
}'''
c = re.sub(r'resolve_bootstrap_base\(\) \{.*?\n\}', new_api_func, c, flags=re.DOTALL, count=1)
# 拔除可能残余的 SHA 强校验
c = re.sub(r'\s*if ! download_file \\\s*"\$REPO_RAW_BASE/SHA256SUMS".*?return 1\s*fi', '', c, flags=re.DOTALL)
c = re.sub(r'\s*if ! verify_bootstrap_checksums "\$boot_dir"; then.*?return 1\s*fi', '', c, flags=re.DOTALL)
with open('install.sh', 'w', encoding='utf-8') as f: f.write(c)

# ==================== 2. 修复 03_env_core.sh：确保 TUIC 探针就绪 ====================
with open('lib/03_env_core.sh', 'r', encoding='utf-8') as f: c = f.read()
if 'has_tuic=1' not in c:
    c = c.replace('if jq -e \'.inbounds[] | select(.tag=="vless-in")\' /etc/sing-box/config.json >/dev/null 2>&1; then has_vless=1; fi', 
                  'if jq -e \'.inbounds[] | select(.tag=="vless-in")\' /etc/sing-box/config.json >/dev/null 2>&1; then has_vless=1; fi\n        if jq -e \'.inbounds[] | select(.tag=="tuic-in")\' /etc/sing-box/config.json >/dev/null 2>&1; then has_tuic=1; fi')
    c = c.replace('has_vless=0\n    if', 'has_vless=0\n    has_tuic=0\n    if')
with open('lib/03_env_core.sh', 'w', encoding='utf-8') as f: f.write(c)

# ==================== 3. 重构 04_install_nodes.sh：解绑依赖检查，追加 TUIC 显式选项 ====================
with open('lib/04_install_nodes.sh', 'r', encoding='utf-8') as f: c = f.read()
c = c.split('inst_singbox() {')[0]
new_code = '''inst_tuic() {
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
    yellow "  TUIC v5 极速协议网络配置"
    read_free_port " ${LIGHT_YELLOW} ▶ 设置 TUIC 主端口 (UDP) [10000-65535] (回车随机): ${PLAIN}" "random" 10000 65535 "udp" "TUIC 主端口" || return 1
    local port="$READ_PORT_RESULT"
    green " 节点主端口已设置为: $port (UDP)"
    open_port "$port" "udp" "tuic-in"
    echo ""
    
    local t_uuid=$(/usr/local/bin/sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr 'A-Z' 'a-z')
    local t_pwd=$(gen_random_str 16)
    local t_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.bing.com")
    
    printf "%b" " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 TUIC_Node]: ${PLAIN}"
    read custom_node_name || exit 1
    [[ -z $custom_node_name ]] && custom_node_name="TUIC_Node"
    echo "$custom_node_name" > /etc/sing-box/tuic_name.txt
    
    local listen_addr="::"
    [[ ! -f /proc/net/if_inet6 ]] && listen_addr="0.0.0.0"

    if ! _begin_singbox_config_transaction; then
        red " [错误] 无法创建配置事务备份。"
        return 1
    fi

    jq --arg p "$port" --arg uuid "$t_uuid" --arg pwd "$t_pwd" --arg cp "/etc/sing-box/cert.crt" --arg kp "/etc/sing-box/private.key" --arg listen "$listen_addr" '
    .inbounds += [{
      "type": "tuic",
      "tag": "tuic-in",
      "listen": $listen,
      "listen_port": ($p | tonumber),
      "users": [{"uuid": $uuid, "password": $pwd}],
      "congestion_control": "bbr",
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cp, "key_path": $kp }
    }]' /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_tuic.json" && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_tuic.json" /etc/sing-box/config.json || {
        _abort_singbox_config_update "TUIC 配置写入失败"
        return 1
    }
    
    _secure_singbox_runtime_permissions >/dev/null 2>&1 || chmod 600 /etc/sing-box/config.json
    svc_enable sing-box >/dev/null 2>&1 || true
    restart_singbox_checked || return 1
    generate_client_configs
    
    echo ""
    green "  [✔] TUIC v5 极速核心部署成功！"
    sleep 2
}

inst_singbox() {
    if [[ ! -x /usr/local/bin/sing-box ]]; then
        echo ""
        red "  [阻断] 未检测到 Sing-box 核心！请先在主菜单执行 [1] 安装前置系统依赖与核心。"
        sleep 2; return
    fi

    normalize_singbox_config
    check_installed_nodes
    
    if [[ $has_hy2 -eq 1 && $has_vless -eq 1 && $has_tuic -eq 1 ]]; then
        echo ""
        red "  [阻断] 您已成功部署了所有支持的节点类型，无需重复安装！"
        sleep 2; return
    fi
    
    clear
    echo ""
    green " ──────────────────────────────────────────────────────────"
    green "                 底层代理协议选择配置                      "
    green " ──────────────────────────────────────────────────────────"
    echo ""
    yellow "  请选择要部署的节点协议："
    echo ""
    [[ $has_hy2 -eq 0 ]] && printf "%b\\n" "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}Hysteria 2 (基于 UDP/QUIC，极速抗丢包，默认推荐)${PLAIN}"
    [[ $has_vless -eq 0 ]] && printf "%b\\n" "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_PURPLE}VLESS + Reality (基于 TCP/XTLS，指纹级伪装，抗封锁推荐)${PLAIN}"
    [[ $has_tuic -eq 0 ]] && printf "%b\\n" "    ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_CYAN}TUIC v5 (基于 UDP/QUIC，极速轻量化协议)${PLAIN}"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [1-3] (默认1): ${PLAIN}"
    read protoInput || protoInput=1
    [[ -z "$protoInput" ]] && protoInput=1

    case "$protoInput" in
        1) [[ $has_hy2 -eq 0 ]] && inst_hysteria2 || { red " 已安装该节点"; sleep 1; } ;;
        2) [[ $has_vless -eq 0 ]] && inst_vless_reality || { red " 已安装该节点"; sleep 1; } ;;
        3) [[ $has_tuic -eq 0 ]] && inst_tuic || { red " 已安装该节点"; sleep 1; } ;;
        *) inst_hysteria2 ;;
    esac
}
'''
with open('lib/04_install_nodes.sh', 'w', encoding='utf-8') as f: f.write(c + new_code)

# ==================== 4. 连接 05_subscription.sh：注入 TUIC 订阅生成 ====================
with open('lib/05_subscription.sh', 'r', encoding='utf-8') as f: c = f.read()
if '聚合: TUIC' not in c:
    c = c.replace('if [[ $has_hy2 -eq 0 && $has_vless -eq 0 ]]; then', 'if [[ $has_hy2 -eq 0 && $has_vless -eq 0 && $has_tuic -eq 0 ]]; then')
    tuic_sub = '''
    # ================= 聚合: TUIC =================
    if [[ $has_tuic -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/tuic_name.txt 2>/dev/null || echo "TUIC_Node")
        local yaml_node_name="${node_name//\\'/\'\'}"
        local safe_node_name=$(jq -nr --arg v "$node_name" '$v|@uri')
        local bind_port=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.listen_port // empty) | tostring] | first // ""' /etc/sing-box/config.json 2>/dev/null)
        local uuid=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.users[0].uuid // empty) | tostring] | first // ""' /etc/sing-box/config.json 2>/dev/null)
        local pwd=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.users[0].password // empty) | tostring] | first // ""' /etc/sing-box/config.json 2>/dev/null)
        local sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.bing.com")
        
        if [[ -n "$bind_port" && -n "$uuid" ]]; then
            local url="tuic://${uuid}:${pwd}@$(get_link_ip):${bind_port}/?sni=${sni}&alpn=h3&congestion_control=bbr#${safe_node_name}"
            url_all="${url_all}${url}\\n"

            proxy_yaml="${proxy_yaml}\\n  - name: '${yaml_node_name}'\\n    type: tuic\\n    server: \\"$yaml_json_ip\\"\\n    port: $bind_port\\n    uuid: \\"$uuid\\"\\n    password: \\"$pwd\\"\\n    sni: \\"$sni\\"\\n    alpn: [h3]\\n    skip-cert-verify: true\\n    reduce-rtt: true\\n    udp-relay-mode: native"
            proxy_names="${proxy_names}\\n      - '${yaml_node_name}'"

            local sb_tuic_json=$(jq -cn --arg tag "$node_name" --arg server "$yaml_json_ip" --arg port "$bind_port" --arg uuid "$uuid" --arg password "$pwd" --arg sni "$sni" '{type: "tuic", tag: $tag, server: $server, server_port: ($port | tonumber), uuid: $uuid, password: $password, congestion_control: "bbr", tls: {enabled: true, server_name: $sni, insecure: true, alpn: ["h3"]}}')
            sb_outbounds=$(jq -cn --argjson current "$sb_outbounds" --argjson item "$sb_tuic_json" '$current + [$item]')
            sb_tags=$(jq -cn --argjson current "$sb_tags" --arg tag "$node_name" '$current + [$tag]')
        fi
    fi
'''
    c = c.replace('    # 修复 Bug 3：正确输出文本流', tuic_sub + '    # 修复 Bug 3：正确输出文本流')
    c = c.replace('close_port_by_tag "vless-in"', 'close_port_by_tag "vless-in"\n    close_port_by_tag "tuic-in"')
with open('lib/05_subscription.sh', 'w', encoding='utf-8') as f: f.write(c)

# ==================== 5. 重排 06_panel_tools.sh：适配 TUIC 卸载与改名 ====================
with open('lib/06_panel_tools.sh', 'r', encoding='utf-8') as f: c = f.read()
c = c.replace('[[ ${has_vless:-0} -eq 1 ]] && echo -e " ${LIGHT_GREEN}[2]${PLAIN} 仅卸载 VLESS 节点 (保留 Hysteria 2 配置)"',
              '[[ ${has_vless:-0} -eq 1 ]] && echo -e " ${LIGHT_GREEN}[2]${PLAIN} 仅卸载 VLESS 节点"\n    [[ ${has_tuic:-0} -eq 1 ]] && echo -e " ${LIGHT_GREEN}[3]${PLAIN} 仅卸载 TUIC v5 节点"')
c = c.replace('echo -e " ${LIGHT_GREEN}[3]${PLAIN} 卸载全部节点与订阅服务 (清空所有入站，保留 Sing-box 核心)"',
              'echo -e " ${LIGHT_GREEN}[4]${PLAIN} 卸载全部节点与订阅服务 (保留 Sing-box 核心)"')
c = c.replace('请输入选项 [0-3]:', '请输入选项 [0-4]:')

old_case = re.search(r'case "\$rm_choice" in.*?esac', c, re.DOTALL).group(0)
new_case = '''case "$rm_choice" in
    1)
        [[ ${has_hy2:-0} -eq 0 ]] && return
        if [[ ${has_vless:-0} -eq 0 && ${has_tuic:-0} -eq 0 ]]; then
            yellow " [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
            clean_env "keep_core"
            green " [✔] Hysteria 2 节点已成功卸载！(核心已保留)"
        else
            _remove_single_node_safe "hy2-in" "Hysteria 2" || return 1
        fi
        _restart_panel_after_node_change
        ;;
    2)
        [[ ${has_vless:-0} -eq 0 ]] && return
        if [[ ${has_hy2:-0} -eq 0 && ${has_tuic:-0} -eq 0 ]]; then
            yellow " [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
            clean_env "keep_core"
            green " [✔] VLESS 节点已成功卸载！(核心已保留)"
        else
            _remove_single_node_safe "vless-in" "VLESS" || return 1
        fi
        _restart_panel_after_node_change
        ;;
    3)
        [[ ${has_tuic:-0} -eq 0 ]] && return
        if [[ ${has_hy2:-0} -eq 0 && ${has_vless:-0} -eq 0 ]]; then
            yellow " [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
            clean_env "keep_core"
            green " [✔] TUIC v5 节点已成功卸载！(核心已保留)"
        else
            _remove_single_node_safe "tuic-in" "TUIC v5" || return 1
        fi
        _restart_panel_after_node_change
        ;;
    4)
        clean_env "keep_core"
        green " [✔] 所有节点配置、订阅及防火墙规则已被彻底清理！(核心已保留)"
        _restart_panel_after_node_change
        ;;
    0) return ;;
    *) red " 输入无效"; sleep 1; return ;;
esac'''
c = c.replace(old_case, new_case)

c = c.replace('elif [[ "$tag" == "vless-in" ]]; then\n            close_port_by_tag "vless-in" || true\n            rm -f /etc/sing-box/vless_name.txt /etc/sing-box/vless_sni.txt /etc/sing-box/reality_pub.txt /etc/sing-box/reality_priv.txt\n        fi',
              'elif [[ "$tag" == "vless-in" ]]; then\n            close_port_by_tag "vless-in" || true\n            rm -f /etc/sing-box/vless_name.txt /etc/sing-box/vless_sni.txt /etc/sing-box/reality_pub.txt /etc/sing-box/reality_priv.txt\n        elif [[ "$tag" == "tuic-in" ]]; then\n            close_port_by_tag "tuic-in" || true\n            rm -f /etc/sing-box/tuic_name.txt\n        fi')

old_modify = re.search(r'local target_node="0"\n\s*if \[\[ \$has_hy2 -eq 1 && \$has_vless -eq 1 \]\].*?protocol="VLESS"\n\s*fi', c, re.DOTALL).group(0)
new_modify = '''local target_node="0"
    yellow " 请选择要修改名称的节点："
    [[ $has_hy2 -eq 1 ]] && printf "%b\\n" "   ${LIGHT_GREEN}[1]${PLAIN} Hysteria 2"
    [[ $has_vless -eq 1 ]] && printf "%b\\n" "   ${LIGHT_GREEN}[2]${PLAIN} VLESS"
    [[ $has_tuic -eq 1 ]] && printf "%b\\n" "   ${LIGHT_GREEN}[3]${PLAIN} TUIC v5"
    printf "%b" " ${LIGHT_YELLOW} ▶ 请选择: ${PLAIN}"
    read target_node
    
    local current_name new_name file_path protocol
    if [[ "$target_node" == "1" && $has_hy2 -eq 1 ]]; then
        file_path="/etc/sing-box/hy2_name.txt"
        current_name=$(cat "$file_path" 2>/dev/null || echo "Hy2_Node")
        protocol="Hysteria 2"
    elif [[ "$target_node" == "2" && $has_vless -eq 1 ]]; then
        file_path="/etc/sing-box/vless_name.txt"
        current_name=$(cat "$file_path" 2>/dev/null || echo "Vless_Node")
        protocol="VLESS"
    elif [[ "$target_node" == "3" && $has_tuic -eq 1 ]]; then
        file_path="/etc/sing-box/tuic_name.txt"
        current_name=$(cat "$file_path" 2>/dev/null || echo "TUIC_Node")
        protocol="TUIC v5"
    else
        red " 输入无效或对应节点未安装"; sleep 1; return
    fi'''
c = c.replace(old_modify, new_modify)
with open('lib/06_panel_tools.sh', 'w', encoding='utf-8') as f: f.write(c)

# ==================== 6. 连接 07_menu.sh：挂载独立 run_check_env，重排 1-12 菜单 ====================
with open('lib/07_menu.sh', 'r', encoding='utf-8') as f: c = f.read()

if 'run_check_env()' not in c:
    c = c.replace('menu() {', 'run_check_env() {\n    check_env\n    echo ""\n    printf "%b" " ${LIGHT_YELLOW} ▶ 前置依赖与核心安装完成，按回车键返回主菜单...${PLAIN}"\n    read temp\n}\n\nmenu() {')

if 'TUIC v5' not in c:
    tuic_status = '''    local tuic_port=$(jq -r '.inbounds[]? | select(.tag=="tuic-in") | .listen_port // empty' /etc/sing-box/config.json 2>/dev/null)
    if [[ -n "$tuic_port" && "$tuic_port" != "null" ]]; then
        local tuic_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "未读取")
        printf "%b\\n" " ${LIGHT_GREEN} ✔ [ TUIC v5      ]${PLAIN} 端口:${LIGHT_YELLOW}${tuic_port}${PLAIN}  证书域名:${LIGHT_YELLOW}${tuic_sni}${PLAIN}  拥塞控制:${LIGHT_YELLOW}bbr${PLAIN}"
    fi\n'''
    c = c.replace('    echo ""\n    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"', tuic_status + '    echo ""\n    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"')

old_menu_block = re.search(r'printf "%b\\n" " \$\{LIGHT_GREEN\}\[1\].*?esac', c, re.DOTALL).group(0)
new_menu_block = '''printf "%b\\n" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_CYAN}安装前置系统依赖与 Sing-box 核心 (首次部署必点)${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_GREEN}安装部署 节点协议 (Hy2 / VLESS / TUIC)${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\\n" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\\n" " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_CYAN}检查 / 在线更新脚本${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[11]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  printf "%b\\n" " ${LIGHT_GREEN}[12]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\\n" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出控制面板${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-12]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in
      0 ) exit 0 ;;
      1 ) run_check_env ;;
      2 ) inst_singbox ;;
      3 ) remove_node ;;
      4 ) singbox_switch ;;
      5 ) config_modify_menu ;;
      6 ) warp_ipv6_route_menu ;;
      7 ) config_outbound ;;
      8 ) showconf ;;
      9 ) self_update ;;
      10 ) enable_bbr ;;
      11 ) quick_repair_and_status ;;
      12 ) global_uninstall ;;
      * ) red " 输入无效"; sleep 1 ;;
  esac'''
c = c.replace(old_menu_block, new_menu_block)
with open('lib/07_menu.sh', 'w', encoding='utf-8') as f: f.write(c)

print("  [✔] 极其硬核的架构重装与解链操作全部执行完毕！")
