#!/usr/bin/env bash
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
#  7. 二级管控面板与辅助工具
# =================================================================
remove_node() {
    check_installed_nodes

    if [[ ${has_hy2:-0} -eq 0 && ${has_vless:-0} -eq 0 ]]; then
        red " 未检测到任何已部署的节点！"
        sleep 2
        return
    fi

    clear
    print_line
    green " 节点安全卸载与清理管控 "
    print_line
    echo ""
    yellow " 检测到当前系统已部署以下节点："
    [[ ${has_hy2:-0} -eq 1 ]] && green " ▶ Hysteria 2 : 运行中"
    [[ ${has_vless:-0} -eq 1 ]] && green " ▶ VLESS : 运行中"
    echo ""
    yellow " 请选择需要执行的卸载操作："
    echo ""
    [[ ${has_hy2:-0} -eq 1 ]] && echo -e " ${LIGHT_GREEN}[1]${PLAIN} 仅卸载 Hysteria 2 节点 (保留 VLESS 配置)"
    [[ ${has_vless:-0} -eq 1 ]] && echo -e " ${LIGHT_GREEN}[2]${PLAIN} 仅卸载 VLESS 节点 (保留 Hysteria 2 配置)"
    echo -e " ${LIGHT_GREEN}[3]${PLAIN} 卸载全部节点与订阅服务 (清空所有入站，保留 Sing-box 核心)"
    echo ""
    echo -e " ${LIGHT_GREEN}[0]${PLAIN} 返回主菜单"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-3]: ${PLAIN}"
    read rm_choice || return

    _remove_single_node_safe() {
        local tag="$1"
        local title="$2"
        local tmp_dir="${HY2_CONFIG_TMP_DIR:-/etc/sing-box/.tmp}"
        local tmp=""

        if [[ ! -f /etc/sing-box/config.json ]]; then
            red " [错误] 未找到 /etc/sing-box/config.json，无法卸载节点。"
            return 1
        fi

        if ! _prepare_config_tmp_dir >/dev/null 2>&1; then
            install -d -m 700 "$tmp_dir" 2>/dev/null || {
                red " [错误] 无法准备配置临时目录。"
                return 1
            }
        fi

        tmp="$(mktemp "$tmp_dir/sb_remove_${tag}.XXXXXX")" || {
            red " [错误] 无法创建卸载临时配置。"
            return 1
        }

        if ! _begin_singbox_config_transaction; then
            rm -f "$tmp"
            red " [错误] 无法创建卸载事务备份。"
            return 1
        fi

        yellow " 正在卸载 ${title} 节点..."

        if ! jq --arg tag "$tag" '
            def _has_inbound($tag):
                (.inbound? // empty) as $in
                | if (($in | type) == "array") then (($in | index($tag)) != null)
                  elif (($in | type) == "string") then ($in == $tag)
                  else false end;

            del(.inbounds[]? | select(.tag == $tag))
            | if ((.route.rules? | type) == "array")
              then .route.rules |= map(select((_has_inbound($tag) | not)))
              else .
              end
        ' /etc/sing-box/config.json > "$tmp"; then
            rm -f "$tmp"
            _abort_singbox_config_update "生成卸载后的 Sing-box 配置失败"
            return 1
        fi

        if [[ ! -s "$tmp" ]] || ! jq empty "$tmp" >/dev/null 2>&1; then
            rm -f "$tmp"
            _abort_singbox_config_update "卸载后的 JSON 配置无效"
            return 1
        fi

        if ! mv -f "$tmp" /etc/sing-box/config.json; then
            rm -f "$tmp"
            _abort_singbox_config_update "无法写入卸载后的 Sing-box 配置"
            return 1
        fi

        _secure_singbox_runtime_permissions >/dev/null 2>&1 || chmod 600 /etc/sing-box/config.json 2>/dev/null || true

        if ! restart_singbox_checked; then
            red " [错误] 卸载后 Sing-box 配置应用失败，已自动回滚。"
            return 1
        fi

        yellow " 正在强制重启 Sing-box 核心，释放已删除节点端口..."
        if ! svc_restart sing-box >/dev/null 2>&1; then
            svc_stop sing-box >/dev/null 2>&1 || true
            sleep 1
            svc_start sing-box >/dev/null 2>&1 || {
                red " [错误] Sing-box 核心强制重启失败。"
                return 1
            }
        fi

        sleep 1
        if ! is_svc_active sing-box; then
            red " [错误] Sing-box 核心重启后未处于运行状态。"
            return 1
        fi

        if [[ "$tag" == "hy2-in" ]]; then
            disable_hy2_port_hopping "quiet" || true
            close_port_by_tag "hy2-in" || true
            rm -f /etc/sing-box/hy2_name.txt /etc/sing-box/hy2_hop_ports.txt
        elif [[ "$tag" == "vless-in" ]]; then
            close_port_by_tag "vless-in" || true
            rm -f /etc/sing-box/vless_name.txt /etc/sing-box/vless_sni.txt /etc/sing-box/reality_pub.txt /etc/sing-box/reality_priv.txt
        fi

        generate_client_configs || yellow " [提示] 节点已卸载，但订阅刷新失败；请稍后进入菜单 [6] 查看订阅时自动刷新。"

        green " [✔] ${title} 节点已成功卸载，Sing-box 核心已重启！"
        return 0
    }

    _restart_panel_after_node_change() {
        local entry="${SCRIPT_PATH:-/opt/hy2-vless-install/install.sh}"
        [[ -f "$entry" ]] || entry="/opt/hy2-vless-install/install.sh"

        yellow " 正在刷新管理脚本状态..."
        sleep 1

        if [[ -f "$entry" ]]; then
            exec bash "$entry"
        fi
    }

    case "$rm_choice" in
        1)
            [[ ${has_hy2:-0} -eq 0 ]] && return
            if [[ ${has_vless:-0} -eq 0 ]]; then
                yellow " [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
                clean_env "keep_core"
                green " [✔] Hysteria 2 节点及关联服务已成功卸载！(核心已保留)"
            else
                _remove_single_node_safe "hy2-in" "Hysteria 2" || return 1
            fi
            _restart_panel_after_node_change
            ;;
        2)
            [[ ${has_vless:-0} -eq 0 ]] && return
            if [[ ${has_hy2:-0} -eq 0 ]]; then
                yellow " [提示] 侦测到您正在卸载仅存的最后一个节点，将自动转为全量网络环境清理..."
                clean_env "keep_core"
                green " [✔] VLESS 节点及关联服务已成功卸载！(核心已保留)"
            else
                _remove_single_node_safe "vless-in" "VLESS" || return 1
            fi
            _restart_panel_after_node_change
            ;;
        3)
            clean_env "keep_core"
            green " [✔] 所有节点配置、订阅及防火墙规则已被彻底清理！(核心已保留)"
            _restart_panel_after_node_change
            ;;
        0)
            return
            ;;
        *)
            red " 输入无效"
            sleep 1
            return
            ;;
    esac
}


global_uninstall() {
    echo ""
    red "  [警告] 这将彻底删除 Sing-box 核心、所有节点配置及 666 快捷命令！"
    printf "%b" " ${LIGHT_YELLOW} ▶ 是否确认全局卸载并回归没装脚本的状态？(y/n) [默认: n]: ${PLAIN}"
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
    printf "%b" " ${LIGHT_YELLOW} ▶ 是否需要修改配置文件？(y/n) [默认: n]: ${PLAIN}"
    read edit_choice || exit 1
    if [[ "$edit_choice" == "y" || "$edit_choice" == "Y" ]]; then
        local config_bak
  config_bak="$(mktemp /etc/sing-box/config.json.bak.XXXXXX)" || { red " [✘] 无法创建配置备份文件。"; return 1; }
  cp -a /etc/sing-box/config.json "$config_bak"
        
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
            mv -f -- "$config_bak" /etc/sing-box/config.json
            sleep 3
        else
            restart_singbox_checked
            sleep 1
            if is_svc_active sing-box; then
                green "  [✔] 重启成功！新配置已生效。"
                generate_client_configs
            else
                red "  [✘] 核心拒绝启动！已恢复修改前的配置。"
                mv -f -- "$config_bak" /etc/sing-box/config.json
                svc_stop sing-box
                svc_start sing-box
            fi
        fi
    fi
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

config_outbound() {
    clear
    echo ""
    print_line
    green " Sing-box 落地代理与分流 (IP 中转) 设置 "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red " 未检测到 Sing-box 配置文件，请先安装！"
        sleep 2
        return
    fi

    local outbound_tmp_dir=""
    local outbound_block_tmp=""
    local config_tmp=""
    local outbound_jq_err=""

    _outbound_pause() {
        echo ""
        printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回菜单...${PLAIN}"
        read _tmp_wait || true
    }

    _outbound_cleanup() {
        [[ -n "$outbound_tmp_dir" && -d "$outbound_tmp_dir" ]] && rm -rf -- "$outbound_tmp_dir"
    }

    _prepare_config_tmp_dir || {
        red " [错误] 无法准备私有配置临时目录。"
        _outbound_pause
        return 1
    }

    outbound_tmp_dir="$(mktemp -d "$HY2_CONFIG_TMP_DIR/panel_outbound.XXXXXX")" || {
        red " [错误] 无法创建落地代理私有临时目录。"
        _outbound_pause
        return 1
    }

    chmod 0700 "$outbound_tmp_dir" || {
        red " [错误] 无法保护落地代理临时目录。"
        _outbound_cleanup
        _outbound_pause
        return 1
    }

    outbound_block_tmp="$outbound_tmp_dir/outbound_block.json"
    config_tmp="$outbound_tmp_dir/config.json"
    outbound_jq_err="$outbound_tmp_dir/jq.err"

    local current_outbound=""
    current_outbound="$(jq -r '[.outbounds[]? | select(.tag=="proxy") | (.type // empty)] | first // ""' /etc/sing-box/config.json 2>/dev/null)"

    if [[ -n "$current_outbound" && "$current_outbound" != "null" ]]; then
        local out_server=""
        local is_tls=""
        local display_type=""
        local is_global="智能分流"

        out_server="$(jq -r '[.outbounds[]? | select(.tag=="proxy") | (.server // empty)] | first // ""' /etc/sing-box/config.json 2>/dev/null)"
        is_tls="$(jq -r '[.outbounds[]? | select(.tag=="proxy") | (.tls.enabled // false)] | first // false' /etc/sing-box/config.json 2>/dev/null)"
        display_type="$current_outbound"
        [[ "$current_outbound" == "http" && "$is_tls" == "true" ]] && display_type="https"

        if jq -e '.route.rules[]? | select((.outbound // "")=="proxy" and .inbound != null)' /etc/sing-box/config.json >/dev/null 2>&1; then
            is_global="指定节点"
        elif jq -e '.route.rules[]? | select((.outbound // "")=="proxy" and (.domain_suffix == null and .domain == null and .ip_cidr == null and .inbound == null))' /etc/sing-box/config.json >/dev/null 2>&1; then
            is_global="全局"
        fi

        yellow " 当前状态: [已开启] 落地代理模式 (类型: ${display_type^^} | 目标: $out_server | 模式: $is_global)"
    else
        green " 当前状态: [未开启] 本机 IP 直连输出"
    fi

    echo ""
    printf "%b\n" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}配置 智能分流代理 (仅 Netflix/ChatGPT 等流媒体走中转)${PLAIN}"
    printf "%b\n" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_CYAN}配置 全局中转代理 (所有出站流量强制走落地中转)${PLAIN}"
    printf "%b\n" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}配置 指定节点中转 (仅让特定节点走落地中转)${PLAIN}"
    printf "%b\n" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_RED}退回 服务器本机直连 (关闭当前落地代理)${PLAIN}"
    echo ""
    printf "%b\n" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-4]: ${PLAIN}"
    read out_choice || {
        _outbound_cleanup
        return
    }

    case "$out_choice" in
        1|2|3)
            echo ""
            yellow " ▶ 请选择落地代理协议类型:"
            printf "%b\n" " ${LIGHT_GREEN}[1]${PLAIN} SOCKS5 (默认)"
            printf "%b\n" " ${LIGHT_GREEN}[2]${PLAIN} HTTP"
            printf "%b\n" " ${LIGHT_GREEN}[3]${PLAIN} HTTPS (HTTP + TLS)"
            printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [1-3] (默认1): ${PLAIN}"
            read proxy_type_choice || proxy_type_choice=1
            [[ -z "$proxy_type_choice" ]] && proxy_type_choice=1

            local proxy_type="socks"
            local proxy_tls="false"

            case "$proxy_type_choice" in
                2)
                    proxy_type="http"
                    proxy_tls="false"
                    ;;
                3)
                    proxy_type="http"
                    proxy_tls="true"
                    ;;
                *)
                    proxy_type="socks"
                    proxy_tls="false"
                    ;;
            esac

            echo ""
            yellow " ▶ 请输入落地代理节点信息:"
            printf "%b" " ${LIGHT_YELLOW} ▶ IP 或 域名: ${PLAIN}"
            read proxy_addr || proxy_addr=""
            if [[ -z "$proxy_addr" ]]; then
                red " [错误] IP 或域名不能为空。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            printf "%b" " ${LIGHT_YELLOW} ▶ 端口: ${PLAIN}"
            read proxy_port || proxy_port=""
            if [[ ! "$proxy_port" =~ ^[0-9]+$ ]] || [ "$proxy_port" -lt 1 ] || [ "$proxy_port" -gt 65535 ]; then
                red " [错误] 端口格式无效！请输入 1-65535。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            printf "%b" " ${LIGHT_YELLOW} ▶ 用户名 (留空为无鉴权): ${PLAIN}"
            read proxy_user || proxy_user=""

            printf "%b" " ${LIGHT_YELLOW} ▶ 密码 (留空为无鉴权): ${PLAIN}"
            read proxy_pass || proxy_pass=""

            local target_inbound=""

            if [[ "$out_choice" == "3" ]]; then
                local has_hy2_cfg=0
                local has_vless_cfg=0

                jq -e '.inbounds[]? | select(.tag=="hy2-in")' /etc/sing-box/config.json >/dev/null 2>&1 && has_hy2_cfg=1
                jq -e '.inbounds[]? | select(.tag=="vless-in")' /etc/sing-box/config.json >/dev/null 2>&1 && has_vless_cfg=1

                if [[ "$has_hy2_cfg" -eq 1 && "$has_vless_cfg" -eq 1 ]]; then
                    echo ""
                    yellow " ▶ 请选择要中转的节点:"
                    printf "%b\n" " ${LIGHT_GREEN}[1]${PLAIN} 仅中转 Hysteria 2"
                    printf "%b\n" " ${LIGHT_GREEN}[2]${PLAIN} 仅中转 VLESS"
                    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [1-2]: ${PLAIN}"
                    read inbound_choice || inbound_choice=1

                    if [[ "$inbound_choice" == "2" ]]; then
                        target_inbound="vless-in"
                    else
                        target_inbound="hy2-in"
                    fi
                elif [[ "$has_hy2_cfg" -eq 1 ]]; then
                    target_inbound="hy2-in"
                elif [[ "$has_vless_cfg" -eq 1 ]]; then
                    target_inbound="vless-in"
                else
                    red " [错误] 未检测到任何节点入站！"
                    _outbound_cleanup
                    _outbound_pause
                    return 1
                fi
            fi

            echo ""
            yellow " 正在生成落地代理 outbound 对象..."

            if ! jq \
                --arg type "$proxy_type" \
                --arg tls "$proxy_tls" \
                --arg addr "$proxy_addr" \
                --arg port "$proxy_port" \
                --arg user "$proxy_user" \
                --arg pass "$proxy_pass" \
                '
                {
                    type: $type,
                    tag: "proxy",
                    server: $addr,
                    server_port: ($port | tonumber),
                    tcp_fast_open: true
                }
                | if $type == "socks" then . + { version: "5" } else . end
                | if $user != "" then . + { username: $user, password: $pass } else . end
                | if $tls == "true" then . + { tls: { enabled: true, server_name: $addr, insecure: true } } else . end
                ' \
                <<<'{}' \
                > "$outbound_block_tmp" \
                2>"$outbound_jq_err"
            then
                red " [错误] 无法生成落地代理对象。"
                [[ -s "$outbound_jq_err" ]] && sed 's/^/ jq: /' "$outbound_jq_err" >&2
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            if ! jq -e '
                type == "object"
                and (.tag == "proxy")
                and (.server | type == "string")
                and (.server | length > 0)
                and (.server_port | type == "number")
                and (.server_port >= 1 and .server_port <= 65535)
                and ((.type == "socks") or (.type == "http"))
            ' "$outbound_block_tmp" >/dev/null 2>&1; then
                red " [错误] 生成的落地代理对象结构无效。"
                cat "$outbound_block_tmp" 2>/dev/null || true
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            if ! _begin_singbox_config_transaction; then
                red " [错误] 无法创建落地代理配置事务备份。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            yellow " 正在写入 Sing-box 落地代理配置..."
            : > "$outbound_jq_err"

            if [[ "$out_choice" == "1" ]]; then
                jq --slurpfile ob "$outbound_block_tmp" '
                    if (.outbounds | type) != "array" then .outbounds = [] else . end
                    | if (.route | type) != "object" then .route = {} else . end
                    | if (.route.rules | type) != "array" then .route.rules = [] else . end
                    | del(.outbounds[]? | select(.tag=="proxy"))
                    | del(.route.rules[]? | select((.outbound // "")=="proxy"))
                    | del(.route.rules[]? | select((.protocol // "")=="dns" and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.port // 0)==53 and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.network // "")=="udp" and (.port // 0)==443))
                    | .outbounds += [$ob[0]]
                    | .route.rules = [
                        {"network": "udp", "port": 443, "action": "route", "outbound": "block"},
                        {"domain_suffix": ["netflix.com", "nflxvideo.net", "openai.com", "chatgpt.com", "disneyplus.com"], "action": "route", "outbound": "proxy"}
                    ] + .route.rules
                ' /etc/sing-box/config.json > "$config_tmp" 2>"$outbound_jq_err"
            elif [[ "$out_choice" == "2" ]]; then
                jq --slurpfile ob "$outbound_block_tmp" '
                    if (.outbounds | type) != "array" then .outbounds = [] else . end
                    | if (.route | type) != "object" then .route = {} else . end
                    | if (.route.rules | type) != "array" then .route.rules = [] else . end
                    | del(.outbounds[]? | select(.tag=="proxy"))
                    | del(.route.rules[]? | select((.outbound // "")=="proxy"))
                    | del(.route.rules[]? | select((.protocol // "")=="dns" and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.port // 0)==53 and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.network // "")=="udp" and (.port // 0)==443))
                    | .outbounds += [$ob[0]]
                    | .route.rules = [
                        {"protocol": "dns", "action": "route", "outbound": "direct"},
                        {"port": 53, "action": "route", "outbound": "direct"},
                        {"network": "udp", "port": 443, "action": "route", "outbound": "block"}
                    ] + .route.rules + [
                        {"action": "route", "outbound": "proxy"}
                    ]
                ' /etc/sing-box/config.json > "$config_tmp" 2>"$outbound_jq_err"
            else
                jq --slurpfile ob "$outbound_block_tmp" --arg inb "$target_inbound" '
                    if (.outbounds | type) != "array" then .outbounds = [] else . end
                    | if (.route | type) != "object" then .route = {} else . end
                    | if (.route.rules | type) != "array" then .route.rules = [] else . end
                    | del(.outbounds[]? | select(.tag=="proxy"))
                    | del(.route.rules[]? | select((.outbound // "")=="proxy"))
                    | del(.route.rules[]? | select((.protocol // "")=="dns" and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.port // 0)==53 and (.outbound // "")=="direct"))
                    | del(.route.rules[]? | select((.network // "")=="udp" and (.port // 0)==443))
                    | .outbounds += [$ob[0]]
                    | .route.rules = [
                        {"inbound": [$inb], "action": "route", "outbound": "proxy"}
                    ] + .route.rules
                ' /etc/sing-box/config.json > "$config_tmp" 2>"$outbound_jq_err"
            fi

            if [[ ! -s "$config_tmp" ]] || ! jq empty "$config_tmp" >/dev/null 2>&1; then
                _abort_singbox_config_update "落地代理配置生成或 JSON 校验失败"
                [[ -s "$outbound_jq_err" ]] && sed 's/^/ jq: /' "$outbound_jq_err" >&2
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            if ! mv -f -- "$config_tmp" /etc/sing-box/config.json; then
                _abort_singbox_config_update "无法发布落地代理配置"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi
            config_tmp=""

            _secure_singbox_runtime_permissions >/dev/null 2>&1 || chmod 600 /etc/sing-box/config.json 2>/dev/null || true

            if restart_singbox_checked; then
                sleep 1
                if is_svc_active sing-box; then
                    green " [✔] 重启成功！落地代理规则已全面生效。"
                else
                    red " [✘] 新配置应用后服务未处于运行状态。"
                fi
            else
                red " [✘] 拦截生效：发现配置错误，已回滚以防断网。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi
            ;;

        4)
            if ! _begin_singbox_config_transaction; then
                red " [错误] 无法创建关闭代理配置事务备份。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            yellow " 正在清除中转路由配置..."

            jq '
                if (.outbounds | type) != "array" then .outbounds = [] else . end
                    | if (.route | type) != "object" then .route = {} else . end
                    | if (.route.rules | type) != "array" then .route.rules = [] else . end
                | del(.outbounds[]? | select(.tag=="proxy"))
                | del(.route.rules[]? | select((.outbound // "")=="proxy"))
                | del(.route.rules[]? | select((.protocol // "")=="dns" and (.outbound // "")=="direct"))
                | del(.route.rules[]? | select((.port // 0)==53 and (.outbound // "")=="direct"))
                | del(.route.rules[]? | select((.network // "")=="udp" and (.port // 0)==443))
            ' /etc/sing-box/config.json > "$config_tmp" 2>"$outbound_jq_err"

            if [[ ! -s "$config_tmp" ]] || ! jq empty "$config_tmp" >/dev/null 2>&1; then
                _abort_singbox_config_update "关闭落地代理配置生成或 JSON 校验失败"
                [[ -s "$outbound_jq_err" ]] && sed 's/^/ jq: /' "$outbound_jq_err" >&2
                _outbound_cleanup
                _outbound_pause
                return 1
            fi

            if ! mv -f -- "$config_tmp" /etc/sing-box/config.json; then
                _abort_singbox_config_update "无法发布关闭落地代理配置"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi
            config_tmp=""

            _secure_singbox_runtime_permissions >/dev/null 2>&1 || chmod 600 /etc/sing-box/config.json 2>/dev/null || true

            if restart_singbox_checked; then
                sleep 1
                green " [✔] 重启成功！已安全退回服务器本机 IP 直连输出模式。"
            else
                red " [✘] 恢复失败：配置文件校验未通过，已回滚以防断网。"
                _outbound_cleanup
                _outbound_pause
                return 1
            fi
            ;;

        0)
            _outbound_cleanup
            return
            ;;

        *)
            red " 输入无效"
            _outbound_cleanup
            _outbound_pause
            return
            ;;
    esac

    _outbound_cleanup

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单...${PLAIN}"
    read temp || true
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
        printf "%b
" "${LIGHT_GREEN}    /usr/local/bin/sing-box check -c /etc/sing-box/config.json${PLAIN}"
        printf "%b
" "${LIGHT_GREEN}    jq '.inbounds[]?.tag' /etc/sing-box/config.json${PLAIN}"
        if [[ $SYSTEM == "Alpine" ]]; then
            printf "%b
" "${LIGHT_GREEN}    tail -n 80 /var/log/sing-box.log${PLAIN}"
        else
            printf "%b
" "${LIGHT_GREEN}    journalctl -u sing-box -n 80 --no-pager${PLAIN}"
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
        printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
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
    printf "%b
" "${LIGHT_GREEN}${raw_url}${PLAIN}"
    echo ""

    print_line
    yellow "  ▶ 自助排障与安全特性提醒 (必读)："
    printf "%b
" "    ${LIGHT_GREEN}如果订阅链接无法打开，请先确认 VPS 安全组已放行 TCP 订阅端口 ${sub_port}。${PLAIN}"
    printf "%b
" "    ${LIGHT_GREEN}如果 Hy2 节点无法连接，请确认 VPS 安全组已放行对应 UDP 主端口。${PLAIN}"
    printf "%b
" "    ${LIGHT_PURPLE}====================================================${PLAIN}"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
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
net.ipv4.tcp_notsent_lowat=16384
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
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

singbox_switch() {
    clear
    echo ""
    print_line
    green "                      服务运行状态控制                      "
    print_line
    echo ""
    printf "%b
" "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}启动 Sing-box 核心${PLAIN}"
    printf "%b
" "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}停止 Sing-box 核心${PLAIN}"
    printf "%b
" "    ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}重启 Sing-box 及 Nginx 分发服务${PLAIN}"
    echo ""
    printf "%b
" "    ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-6]: ${PLAIN}"
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

    ensure_singbox_core || { printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回... ${PLAIN}"; read temp; return; }
    normalize_singbox_config
    echo ""
    yellow "  正在执行 sing-box 配置校验..."
    if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
        red "  [✘] 配置仍未通过，请复制上面的错误发给我。"
        echo ""
        printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回... ${PLAIN}"
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
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}


apply_singbox_config_with_rollback() {
    local backup="${1:-}"

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red " 未检测到 /etc/sing-box/config.json，请先安装节点。"
        return 1
    fi

    if [[ -z "$backup" || ! -f "$backup" ]]; then
        backup="/etc/sing-box/config.json.bak.$(date +%F-%H%M%S)"
        cp -a /etc/sing-box/config.json "$backup"
    fi

    chmod 600 /etc/sing-box/config.json 2>/dev/null || true

    if ! jq . /etc/sing-box/config.json >/dev/null 2>&1; then
        red " [错误] JSON 结构校验失败，正在回滚。"
        mv -f "$backup" /etc/sing-box/config.json
        return 1
    fi

    if [[ -x /usr/local/bin/sing-box ]]; then
        if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
            red " [错误] sing-box 配置校验失败，正在回滚。"
            mv -f "$backup" /etc/sing-box/config.json
            restart_singbox_checked || true
            return 1
        fi
    fi

    restart_singbox_checked || {
        red " [错误] sing-box 重启失败，正在回滚。"
        mv -f "$backup" /etc/sing-box/config.json
        restart_singbox_checked || true
        return 1
    }

    generate_client_configs
    green " [✔] 配置已生效，订阅已刷新。"
    return 0
}

modify_vless_self_signed_cert() {
    clear
    print_line
    green " 修改 VLESS 节点证书伪装参数 / Reality 密钥 "
    print_line
    echo ""

    check_installed_nodes
    if [[ $has_vless -eq 0 ]]; then
        red " 未检测到 VLESS 节点，请先安装 VLESS。"
        sleep 2
        return
    fi

    ensure_singbox_core || return 1

    local current_sni new_sni keypair_json v_private_key v_public_key v_short_id backup

    current_sni=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config.json 2>/dev/null)
    [[ -z "$current_sni" || "$current_sni" == "null" ]] && current_sni=$(cat /etc/sing-box/vless_sni.txt 2>/dev/null || cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.microsoft.com")

    yellow " 当前 VLESS 伪装域名 / SNI: $current_sni"
    echo ""
    yellow " 请选择新的安全伪装域名 (SNI):"
    printf "%b\n" "    ${LIGHT_GREEN}[1]${PLAIN} www.bing.com"
    printf "%b\n" "    ${LIGHT_GREEN}[2]${PLAIN} www.apple.com"
    printf "%b\n" "    ${LIGHT_GREEN}[3]${PLAIN} www.microsoft.com"
    printf "%b\n" "    ${LIGHT_GREEN}[4]${PLAIN} 自定义输入"
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [1-4] (回车保持原样: $current_sni): ${PLAIN}"
    read sni_choice || sni_choice=0
    [[ -z "$sni_choice" ]] && sni_choice=0

    case $sni_choice in
        1) new_sni="www.bing.com" ;;
        2) new_sni="www.apple.com" ;;
        3) new_sni="www.microsoft.com" ;;
        4)
            printf "%b" " ${LIGHT_YELLOW} ▶ 请输入自定义伪装域名 (如 github.com) [回车保持原样]: ${PLAIN}"
            read new_sni || new_sni="$current_sni"
            [[ -z "$new_sni" ]] && new_sni="$current_sni"
            ;;
        *) new_sni="$current_sni" ;;
    esac

    if [[ ! "$new_sni" =~ ^[A-Za-z0-9.-]+$ ]]; then
        red " [错误] 域名格式不合法。"
        sleep 2
        return
    fi

    yellow " 正在生成新的 Reality keypair 与 short_id..."
    keypair_json=$(/usr/local/bin/sing-box generate reality-keypair 2>/dev/null)
    v_private_key=$(echo "$keypair_json" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    v_public_key=$(echo "$keypair_json" | awk '/PublicKey/ {print $2}' | tr -d '"')
    v_short_id=$(/usr/local/bin/sing-box generate rand --hex 8 2>/dev/null)

    if [[ -z "$v_private_key" || -z "$v_public_key" || -z "$v_short_id" ]]; then
        red " [错误] Reality 密钥生成失败。"
        sleep 2
        return
    fi

    backup="/etc/sing-box/config.json.bak.vless-reality.$(date +%F-%H%M%S)"
    cp -a /etc/sing-box/config.json "$backup"

    if ! jq -e '.inbounds[] | select(.tag=="vless-in")' /etc/sing-box/config.json >/dev/null 2>&1; then
        red " [错误] 配置中未找到 vless-in。"
        sleep 2
        return
    fi

    if ! jq --arg sni "$new_sni" --arg priv "$v_private_key" --arg sid "$v_short_id" '
        (.inbounds[] | select(.tag=="vless-in") | .tls.server_name) = $sni
        | (.inbounds[] | select(.tag=="vless-in") | .tls.reality.private_key) = $priv
        | (.inbounds[] | select(.tag=="vless-in") | .tls.reality.short_id) = [$sid]
        | (.inbounds[] | select(.tag=="vless-in") | .tls.reality.handshake.server) = $sni
    ' /etc/sing-box/config.json > /tmp/sb_vless_reality.json; then
        red " [错误] jq 修改失败。"
        mv -f "$backup" /etc/sing-box/config.json
        sleep 2
        return
    fi

    mv -f /tmp/sb_vless_reality.json /etc/sing-box/config.json

    if apply_singbox_config_with_rollback "$backup"; then
        printf "%s\n" "$v_public_key" > /etc/sing-box/reality_pub.txt.tmp && mv -f /etc/sing-box/reality_pub.txt.tmp /etc/sing-box/reality_pub.txt
        printf "%s\n" "$new_sni" > /etc/sing-box/vless_sni.txt.tmp && mv -f /etc/sing-box/vless_sni.txt.tmp /etc/sing-box/vless_sni.txt
        generate_client_configs
        green " [✔] VLESS 证书伪装参数 / Reality 密钥已更新。"
    else
        red " [错误] VLESS 修改失败，配置已回滚。"
    fi

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回配置修改菜单...${PLAIN}"
    read temp
}


modify_hy2_self_signed_cert() {
    clear
    print_line
    green " 修改 Hysteria 2 自签名证书 "
    print_line
    echo ""

    check_installed_nodes
    if [[ $has_hy2 -eq 0 ]]; then
        red " 未检测到 Hysteria 2 节点，请先安装 Hy2。"
        sleep 2
        return
    fi

    local cert_bak key_bak sni_bak
    cert_bak="/tmp/hy2-cert.crt.bak.$(date +%s)"
    key_bak="/tmp/hy2-private.key.bak.$(date +%s)"
    sni_bak="/tmp/hy2-cert_sni.txt.bak.$(date +%s)"

    [[ -f /etc/sing-box/cert.crt ]] && cp -a /etc/sing-box/cert.crt "$cert_bak"
    [[ -f /etc/sing-box/private.key ]] && cp -a /etc/sing-box/private.key "$key_bak"
    [[ -f /etc/sing-box/cert_sni.txt ]] && cp -a /etc/sing-box/cert_sni.txt "$sni_bak"

    yellow " 当前 Hy2 证书域名: $(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo unknown)"
    echo ""
    yellow " 将重新生成 /etc/sing-box/cert.crt 与 /etc/sing-box/private.key"
    echo ""

    inst_cert || {
        red " [错误] 自签名证书生成失败。"
        sleep 2
        return
    }

    if ! restart_singbox_checked; then
        red " [错误] 新证书应用失败，正在回滚旧证书。"
        [[ -f "$cert_bak" ]] && mv -f "$cert_bak" /etc/sing-box/cert.crt
        [[ -f "$key_bak" ]] && mv -f "$key_bak" /etc/sing-box/private.key
        [[ -f "$sni_bak" ]] && mv -f "$sni_bak" /etc/sing-box/cert_sni.txt
        restart_singbox_checked || true
        sleep 2
        return
    fi

    generate_client_configs
    green " [✔] Hy2 自签名证书已更新，订阅已刷新。"

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回配置修改菜单...${PLAIN}"
    read temp
}

hy2_hop_colon_range() {
    echo "$1" | sed 's/-/:/'
}

remove_hy2_port_hop_rules() {
    local hop_range="$1"
    local main_port="$2"
    local colon_range

    [[ -z "$hop_range" || -z "$main_port" ]] && return 0
    colon_range="$(hy2_hop_colon_range "$hop_range")"

    for tool in iptables ip6tables; do
        command -v "$tool" >/dev/null 2>&1 || continue

        while "$tool" -t nat -C PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null; do
            "$tool" -t nat -D PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null || break
        done

        while "$tool" -C INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null; do
            "$tool" -D INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null || break
        done
    done
}

apply_hy2_port_hop_rules() {
    local hop_range="$1"
    local main_port="$2"
    local colon_range

    colon_range="$(hy2_hop_colon_range "$hop_range")"

    if ! command -v iptables >/dev/null 2>&1; then
        red " [错误] 未检测到 iptables，无法设置 Hy2 跳跃端口转发。"
        return 1
    fi

    for tool in iptables ip6tables; do
        command -v "$tool" >/dev/null 2>&1 || continue

        "$tool" -C INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null \
            || "$tool" -A INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null || true

        "$tool" -t nat -C PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null \
            || "$tool" -t nat -A PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null || true
    done

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${hop_range}/udp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        ufw allow "${colon_range}/udp" >/dev/null 2>&1 || true
    fi

    save_iptables || true
    return 0
}

install_hy2_port_hop_service() {
    cat > /usr/local/bin/hy2-port-hop-apply <<'HOPAPPLY'
#!/usr/bin/env bash
set -u

range_file="/etc/sing-box/hy2_hop_ports.txt"
main_file="/etc/sing-box/hy2_hop_main_port.txt"

[[ -f "$range_file" && -f "$main_file" ]] || exit 0

hop_range="$(cat "$range_file" 2>/dev/null | tr -d '[:space:]')"
main_port="$(cat "$main_file" 2>/dev/null | tr -d '[:space:]')"
colon_range="${hop_range/-/:}"

[[ "$hop_range" =~ ^[0-9]+-[0-9]+$ ]] || exit 0
[[ "$main_port" =~ ^[0-9]+$ ]] || exit 0

for tool in iptables ip6tables; do
    command -v "$tool" >/dev/null 2>&1 || continue

    "$tool" -C INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null \
        || "$tool" -A INPUT -p udp --dport "$colon_range" -j ACCEPT 2>/dev/null || true

    "$tool" -t nat -C PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null \
        || "$tool" -t nat -A PREROUTING -p udp --dport "$colon_range" -j REDIRECT --to-ports "$main_port" 2>/dev/null || true
done
HOPAPPLY

    chmod +x /usr/local/bin/hy2-port-hop-apply

    if [[ "${SYSTEM:-}" == "Alpine" ]]; then
        cat > /etc/init.d/hy2-port-hop <<'OPENRC'
#!/sbin/openrc-run
name="hy2-port-hop"
description="Apply Hy2 port hopping NAT rules"
command="/usr/local/bin/hy2-port-hop-apply"
command_background="false"

depend() {
    need net
}
OPENRC
        chmod +x /etc/init.d/hy2-port-hop
        rc-update add hy2-port-hop default >/dev/null 2>&1 || true
        rc-service hy2-port-hop restart >/dev/null 2>&1 || true
    else
        cat > /etc/systemd/system/hy2-port-hop.service <<'SYSTEMD'
[Unit]
Description=Apply Hy2 port hopping NAT rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hy2-port-hop-apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD
        _smart_run "正在重载系统级守护进程配置" systemctl daemon-reload 
        _smart_run "正在重载系统级守护进程配置" systemctl enable --now hy2-port-hop.service
    fi
}

disable_hy2_port_hopping() {
    local quiet="${1:-}"
    local old_range old_main

    old_range=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')
    old_main=$(cat /etc/sing-box/hy2_hop_main_port.txt 2>/dev/null | tr -d '[:space:]')

    remove_hy2_port_hop_rules "$old_range" "$old_main"

    if [[ "${SYSTEM:-}" == "Alpine" ]]; then
        rc-service hy2-port-hop stop >/dev/null 2>&1 || true
        rc-update del hy2-port-hop default >/dev/null 2>&1 || true
        rm -f /etc/init.d/hy2-port-hop
    else
        systemctl disable --now hy2-port-hop.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/hy2-port-hop.service
        _smart_run "正在重载系统级守护进程配置" systemctl daemon-reload 
    fi

    rm -f /usr/local/bin/hy2-port-hop-apply
    rm -f /etc/sing-box/hy2_hop_ports.txt /etc/sing-box/hy2_hop_main_port.txt

    save_iptables || true

    [[ "$quiet" == "quiet" ]] || green " [✔] Hy2 跳跃端口已关闭。"
}

enable_hy2_port_hopping() {
    local _hy2_detected_main_port=""
    _hy2_detected_main_port="$(_hy2_get_main_port 2>/dev/null || true)"

    clear
    print_line
    green " 开启 / 修改 Hysteria 2 跳跃端口 "
    print_line
    echo ""

    check_installed_nodes
    if [[ $has_hy2 -eq 0 ]]; then
        red " 未检测到 Hysteria 2 节点，请先安装 Hy2。"
        sleep 2
        return
    fi

    local main_port old_range hop_range start_port end_port range_size confirm_large old_main
    main_port=$(jq -r '.inbounds[] | select((.tag // "")=="hy2-in" or (.type // "")=="hysteria2") | .listen_port' /etc/sing-box/config.json 2>/dev/null)

    if [[ ! "$main_port" =~ ^[0-9]+$ ]]; then
        red " [错误] 未能读取 Hy2 主端口。"
        sleep 2
        return
    fi

    old_range=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')

    yellow " 当前 Hy2 主端口: $main_port/udp"
    [[ -n "$old_range" ]] && yellow " 当前跳跃端口段: $old_range/udp"
    echo ""
    yellow " 示例: 20000-30000"
    yellow " 注意: VPS 安全组也需要放行这个 UDP 端口段。"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入 Hy2 跳跃端口段 [0 关闭跳跃端口]: ${PLAIN}"
    read hop_range || return

    hop_range="$(echo "$hop_range" | tr -d '[:space:]')"

    if [[ "$hop_range" == "0" ]]; then
        disable_hy2_port_hopping
        generate_client_configs
        echo ""
        printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回配置修改菜单...${PLAIN}"
        read temp
        return
    fi

    if [[ ! "$hop_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        red " [错误] 端口段格式错误，应为 20000-30000。"
        sleep 2
        return
    fi

    start_port="${BASH_REMATCH[1]}"
    end_port="${BASH_REMATCH[2]}"

    if (( start_port < 1 || end_port > 65535 || start_port >= end_port )); then
        red " [错误] 端口段范围无效，必须满足 1 <= 起始端口 < 结束端口 <= 65535。"
        sleep 2
        return
    fi

    range_size=$((end_port - start_port + 1))
    if (( range_size > 10000 )); then
        yellow " [提示] 端口段较大: $range_size 个 UDP 端口。"
        printf "%b" " ${LIGHT_YELLOW} ▶ 是否继续？(y/n) [默认: n]: ${PLAIN}"
        read confirm_large || confirm_large="n"
        [[ -z "$confirm_large" ]] && confirm_large="n"
        if [[ "$confirm_large" != "y" && "$confirm_large" != "Y" ]]; then
            yellow " 已取消。"
            sleep 1
            return
        fi
    fi

    if [[ -n "$old_range" && "$old_range" != "$hop_range" ]]; then
        old_main=$(cat /etc/sing-box/hy2_hop_main_port.txt 2>/dev/null | tr -d '[:space:]')
        remove_hy2_port_hop_rules "$old_range" "$old_main"
    fi

    printf "%s\n" "$hop_range" > /etc/sing-box/hy2_hop_ports.txt.tmp && mv -f /etc/sing-box/hy2_hop_ports.txt.tmp /etc/sing-box/hy2_hop_ports.txt
    printf "%s\n" "$main_port" > /etc/sing-box/hy2_hop_main_port.txt.tmp && mv -f /etc/sing-box/hy2_hop_main_port.txt.tmp /etc/sing-box/hy2_hop_main_port.txt

    if apply_hy2_port_hop_rules "$hop_range" "$main_port"; then
        install_hy2_port_hop_service
        generate_client_configs
        green " [✔] Hy2 跳跃端口已开启: $hop_range/udp -> $main_port/udp"
        yellow " [提示] 请确认云厂商安全组也放行 UDP $hop_range。"
    else
        red " [错误] Hy2 跳跃端口配置失败。"
    fi

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回配置修改菜单...${PLAIN}"
    read temp
}


modify_node_name() {
    clear
    print_line
    green " 修改 节点名称 (展示在客户端中的名字) "
    print_line
    echo ""
    check_installed_nodes
    if [[ $has_hy2 -eq 0 && $has_vless -eq 0 ]]; then
        red " 未检测到任何已部署的节点！"
        sleep 2
        return
    fi

    local target_node="0"
    if [[ $has_hy2 -eq 1 && $has_vless -eq 1 ]]; then
        yellow " 检测到您同时部署了 Hy2 和 VLESS，请选择要修改的节点："
        printf "%b
" "   ${LIGHT_GREEN}[1]${PLAIN} Hysteria 2"
        printf "%b
" "   ${LIGHT_GREEN}[2]${PLAIN} VLESS"
        printf "%b" " ${LIGHT_YELLOW} ▶ 请选择 [1-2]: ${PLAIN}"
        read target_node
        [[ "$target_node" != "1" && "$target_node" != "2" ]] && { red " 输入无效"; sleep 1; return; }
    elif [[ $has_hy2 -eq 1 ]]; then
        target_node="1"
    else
        target_node="2"
    fi

    local current_name new_name file_path protocol
    if [[ "$target_node" == "1" ]]; then
        file_path="/etc/sing-box/hy2_name.txt"
        current_name=$(cat "$file_path" 2>/dev/null || echo "Hy2_Node")
        protocol="Hysteria 2"
    else
        file_path="/etc/sing-box/vless_name.txt"
        current_name=$(cat "$file_path" 2>/dev/null || echo "Vless_Node")
        protocol="VLESS"
    fi

    yellow " 当前 $protocol 节点名称: $current_name"
    printf "%b" " ${LIGHT_YELLOW} ▶ 请输入新的节点名称 (全面支持中文、空格、括号等特殊符号): ${PLAIN}"
    read new_name || return
    [[ -z "$new_name" ]] && return

    # 动态宽松防线：得益于后端的强力转义引擎，此处全面放开字符限制
    if [[ -z "${new_name// /}" ]]; then
        red " [错误] 节点名称不能为空或纯空格！"
        sleep 2
        return
    fi

    printf "%s\n" "$new_name" > "$file_path"
    yellow " 正在重新装配底层订阅引擎..."
    generate_client_configs
    green " [✔] $protocol 节点名称已成功修改为: $new_name (订阅已同步刷新)"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回配置修改菜单...${PLAIN}"
    read temp
}


set_node_expiration() {
    clear
    print_line
    green " 设置 / 延长节点有效期 (定时停用看门狗) "
    print_line
    echo ""
    
    local exp_file="/etc/sing-box/expiration.txt"
    local current_exp=$(cat "$exp_file" 2>/dev/null || echo "0")
    local now=$(date +%s)
    
    if [[ "$current_exp" -gt "$now" ]]; then
        local diff=$((current_exp - now))
        local days=$((diff / 86400))
        yellow " 当前节点处于受控保护中，剩余有效期: $days 天"
    else
        yellow " 当前节点处于 [永久有效] 或 [已到期停用] 状态。"
    fi
    
    echo ""
    printf "%b
" "   ${LIGHT_GREEN}[1]${PLAIN} 设定/续期 有效期天数"
    printf "%b
" "   ${LIGHT_GREEN}[2]${PLAIN} 解除时间限制 (变回永久有效)"
    printf "%b
" "   ${LIGHT_GREEN}[3]${PLAIN} 立即模拟到期触发 (开发排障测试)"
    printf "%b
" "   ${LIGHT_GREEN}[0]${PLAIN} 返回上级菜单"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 请选择操作 [0-3]: ${PLAIN}"
    read exp_choice
    
    case $exp_choice in
        1)
            printf "%b" "\n ${LIGHT_YELLOW} ▶ 请输入有效的限时天数 (正整数，如 30): ${PLAIN}"
            read exp_days
            if [[ ! "$exp_days" =~ ^[0-9]+$ ]] || [ "$exp_days" -lt 1 ]; then
                red " [错误] 输入格式无效！必须是大于0的正整数。"
                sleep 2; return
            fi
            
            local new_exp=$(( now + exp_days * 86400 ))
            printf "%s\n" "$new_exp" > "$exp_file"
            
            # 往系统 crontab 挂载每小时执行的隐形断网看门狗守护进程
            (crontab -l 2>/dev/null | grep -v "expiration.txt"; echo "0 * * * * export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin; exp=\$(cat /etc/sing-box/expiration.txt 2>/dev/null | tr -cd '0-9'); [ -z \"\$exp\" ] && exp=9999999999; if [ \$(date +%s) -ge \$exp ]; then rc-service sing-box stop >/dev/null 2>&1 || systemctl stop sing-box >/dev/null 2>&1; fi") | crontab -
            
            green " [✔] 成功！节点有效期已成功设定为 $exp_days 天。后盾看门狗守护已同步挂载！"
            ;;
        2)
            printf "0\n" > "$exp_file"
            # 清理 crontab 垃圾残骸
            crontab -l 2>/dev/null | grep -v "expiration.txt" | crontab -
            green " [✔] 成功！限制已完全解除，节点恢复为 [永久有效] 状态。"
            ;;
        3)
            # 模拟到期：直接把时间戳写成 1000 
            printf "1000\n" > "$exp_file"
            yellow " 正在触发看门狗强制阻断..."
            rc-service sing-box stop >/dev/null 2>&1 || systemctl stop sing-box >/dev/null 2>&1
            red " [✔] 模拟断网成功！检测到时间回溯，Sing-box 核心已被后台物理击杀！"
            ;;
        *)
            return
            ;;
    esac
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回...${PLAIN}"
    read temp
}

config_modify_menu() {
    while true; do
        clear
        print_line
        green " 查看 / 修改 配置文件 "
        print_line
        echo ""
        printf "%b
" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}修改配置文件${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_YELLOW}修改 VLESS 节点的自签名证书 / Reality 参数${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}修改 Hy2 的自签名证书${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_CYAN}开启 / 修改 Hy2 的跳跃端口${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_BLUE}修改客户端节点名称 (展示名)${PLAIN}"
                printf "%b
" " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_PURPLE}配置节点定时停用限时 (到期自动断网)${PLAIN}"

        printf "%b
" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
        echo ""
        printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-6]: ${PLAIN}"
        read config_modify_choice || return

        case "$config_modify_choice" in
            1) edit_config ;;
            2) modify_vless_self_signed_cert ;;
            3) modify_hy2_self_signed_cert ;;
            4) enable_hy2_port_hopping ;;
            5) modify_node_name ;;
            6) set_node_expiration ;;
            0) return ;;
            *) red " 输入无效"; sleep 1 ;;
        esac
    done
}

detect_public_ipv6_addr() {
    # 直接向内核路由表索要前往公共全球单播地址的真实源出口 IP (完美兼容标准 iproute2 与 BusyBox)
    local route_gate=$(ip -6 route get 2001:4860:4860::8888 2>/dev/null)
    if [[ -n "$route_gate" ]]; then
        echo "$route_gate" | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
    fi
}

detect_warp_ipv6_iface() {
    local configured_iface candidate

    configured_iface=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null | head -n1)
    if [[ -n "$configured_iface" && "$configured_iface" != "null" ]] && ip link show "$configured_iface" >/dev/null 2>&1; then
        echo "$configured_iface"
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

iface_has_ipv6_addr() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1

    ip -6 addr show dev "$iface" scope global 2>/dev/null \
        | awk '/inet6/ {print $2}' \
        | cut -d/ -f1 \
        | grep -Eq '^[23][0-9a-fA-F:]|^2a09:|^2606:|^fd'
}

test_default_ipv6_egress() {
    command -v curl >/dev/null 2>&1 || return 2
    curl -6 --connect-timeout 5 -fsSL https://www.cloudflare.com/cdn-cgi/trace >/tmp/hy2-default-ipv6-trace.txt 2>/dev/null
}

test_iface_ipv6_egress() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1
    command -v curl >/dev/null 2>&1 || return 2
    curl -6 --interface "$iface" --connect-timeout 6 -fsSL https://www.cloudflare.com/cdn-cgi/trace >/tmp/hy2-warp-ipv6-trace.txt 2>/dev/null
}

show_warp_ipv6_status_panel() {
    local public_ipv6 warp_iface configured_iface domains default_status iface_status warp_trace warp_mark

    public_ipv6=$(detect_public_ipv6_addr)
    warp_iface=$(detect_warp_ipv6_iface)

    configured_iface=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null | head -n1)
    domains=$(jq -r '.route.rules[]? | select(.outbound=="warp-ipv6") | .domain_suffix[]? // empty' /etc/sing-box/config.json 2>/dev/null | paste -sd "," -)

    printf "%b
" " ${LIGHT_CYAN}实时 VPS / WARP IPv6 检测面板${PLAIN}"
    printf "%b
" " ${LIGHT_CYAN}──────────────────────────────────────────────────────────${PLAIN}"

    if [[ -n "$public_ipv6" ]]; then
        green " VPS IPv6 地址: 支持 ($public_ipv6)"
    else
        red " VPS IPv6 地址: 未检测到公网 IPv6"
    fi

    if test_default_ipv6_egress; then
        default_status=$(grep -E '^ip=' /tmp/hy2-default-ipv6-trace.txt 2>/dev/null | head -n1 | cut -d= -f2-)
        green " 默认 IPv6 出口: 可用 (${default_status:-已连通})"
    else
        case "$?" in
            2) yellow " 默认 IPv6 出口: 未测试，系统缺少 curl" ;;
            *) red " 默认 IPv6 出口: 不可用" ;;
        esac
    fi

    if [[ -n "$warp_iface" ]]; then
        green " WARP IPv6 接口: 检测到 ($warp_iface)"
        if iface_has_ipv6_addr "$warp_iface"; then
            green " WARP 接口 IPv6 地址: 支持"
        else
            red " WARP 接口 IPv6 地址: 未检测到"
        fi

        if test_iface_ipv6_egress "$warp_iface"; then
            warp_trace=$(grep -E '^ip=' /tmp/hy2-warp-ipv6-trace.txt 2>/dev/null | head -n1 | cut -d= -f2-)
            warp_mark=$(grep -E '^warp=' /tmp/hy2-warp-ipv6-trace.txt 2>/dev/null | head -n1 | cut -d= -f2-)
            green " WARP IPv6 出口: 可用 (${warp_trace:-已连通}, warp=${warp_mark:-unknown})"
        else
            case "$?" in
                2) yellow " WARP IPv6 出口: 未测试，系统缺少 curl" ;;
                *) red " WARP IPv6 出口: 不可用" ;;
            esac
        fi
    else
        red " WARP IPv6 接口: 未检测到"
    fi

    if [[ -n "$configured_iface" && "$configured_iface" != "null" ]]; then
        green " 当前分流状态: 已开启"
        yellow " 当前绑定接口: $configured_iface"
        yellow " 当前分流域名: ${domains:-未读取到}"
    else
        yellow " 当前分流状态: 未开启"
    fi

    if [[ -z "$public_ipv6" && -z "$warp_iface" ]]; then
        echo ""
        red " 结论: 当前 VPS 未检测到 IPv6 / WARP IPv6，不支持开启 IPv6 域名分流。"
    elif [[ -z "$warp_iface" ]]; then
        echo ""
        yellow " 结论: VPS 可能有 IPv6，但未检测到 WARP 接口；请先安装或启动 WARP。"
    else
        echo ""
        green " 结论: 检测到 IPv6/WARP 信息，可尝试开启 WARP IPv6 域名分流。"
    fi

    printf "%b
" " ${LIGHT_CYAN}──────────────────────────────────────────────────────────${PLAIN}"
    echo ""
}

install_or_repair_warp_ipv6_iface() {
    clear
    print_line
    green " 安装 / 修复 WARP IPv6 接口 "
    print_line
    echo ""

    if [[ "$(id -u)" -ne 0 ]]; then
        red " [错误] 请使用 root 用户运行。"
        sleep 2
        return
    fi

    local iface="wgcf"
    local mark="51820"
    local work_dir="/etc/wireguard"
    local tmp_dir="/tmp/wgcf-install.$$"
    local arch wgcf_url wgcf_bin latest_api
    local pkg_ok=0

    yellow " 本功能将安装 wgcf + WireGuard，并创建接口: $iface"
    yellow " 将使用 Table = off + fwmark 策略路由，避免接管系统默认 IPv6。"
    echo ""

    printf "%b" " ${LIGHT_YELLOW} ▶ 是否继续安装 / 修复 WARP IPv6 接口？(y/n) [默认: y]: ${PLAIN}"
    read confirm_install || confirm_install="y"
    [[ -z "$confirm_install" ]] && confirm_install="y"

    if [[ "$confirm_install" != "y" && "$confirm_install" != "Y" ]]; then
        yellow " 已取消。"
        sleep 1
        return
    fi

    mkdir -p "$work_dir" "$tmp_dir"

    yellow " 正在安装依赖: curl jq wireguard-tools iproute2 ca-certificates..."

    if command -v apt-get >/dev/null 2>&1; then
        _smart_run "正在极速同步全局软件源索引" apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq wireguard-tools iproute2 ca-certificates && pkg_ok=1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl jq wireguard-tools iproute ca-certificates && pkg_ok=1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl jq wireguard-tools iproute ca-certificates && pkg_ok=1
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl jq wireguard-tools iproute2 ca-certificates && pkg_ok=1
    rc-update add crond default >/dev/null 2>&1 || true
    rc-service crond start >/dev/null 2>&1 || true
    else
        red " [错误] 未识别的软件包管理器，请手动安装 curl jq wireguard-tools iproute2。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    if [[ "$pkg_ok" -ne 1 ]]; then
        red " [错误] 依赖安装失败。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    if ! command -v wg >/dev/null 2>&1 || ! command -v wg-quick >/dev/null 2>&1; then
        red " [错误] wireguard-tools 未正确安装。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    if ! command -v wgcf >/dev/null 2>&1; then
        yellow " 未检测到 wgcf，正在下载最新版本..."

        case "$(uname -m)" in
            x86_64|amd64) arch="amd64" ;;
            aarch64|arm64) arch="arm64" ;;
            armv7*|armv6*) arch="armv7" ;;
            *) arch="amd64" ;;
        esac

        latest_api="$(curl -fsSL --connect-timeout 10 https://api.github.com/repos/ViRb3/wgcf/releases/latest 2>/dev/null)"

        wgcf_url="$(printf '%s' "$latest_api" \
            | jq -r --arg arch "$arch" '.assets[]? | select(.name | test("linux_" + $arch + "$")) | .browser_download_url' 2>/dev/null \
            | head -n1)"

        if [[ -z "$wgcf_url" || "$wgcf_url" == "null" ]]; then
            wgcf_url="$(printf '%s' "$latest_api" \
                | grep -oE 'https://[^"]+linux_'"$arch" \
                | head -n1)"
        fi

        if [[ -z "$wgcf_url" ]]; then
            red " [错误] 未能获取 wgcf 下载地址。"
            rm -rf "$tmp_dir"
            sleep 2
            return
        fi

        if ! curl -fL --connect-timeout 20 "$wgcf_url" -o "$tmp_dir/wgcf"; then
            red " [错误] wgcf 下载失败。"
            rm -rf "$tmp_dir"
            sleep 2
            return
        fi

        install -m 0755 "$tmp_dir/wgcf" /usr/local/bin/wgcf
    fi

    if ! command -v wgcf >/dev/null 2>&1; then
        red " [错误] wgcf 安装失败。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    yellow " 正在生成 WARP 配置..."

    cd "$tmp_dir" || {
        red " [错误] 无法进入临时目录。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    }

    if [[ ! -f "$work_dir/wgcf-account.toml" ]]; then
        if ! wgcf register --accept-tos; then
            red " [错误] wgcf 注册失败。"
            rm -rf "$tmp_dir"
            sleep 2
            return
        fi
        cp -f wgcf-account.toml "$work_dir/wgcf-account.toml"
    else
        cp -f "$work_dir/wgcf-account.toml" "$tmp_dir/wgcf-account.toml"
    fi

    if ! wgcf generate; then
        red " [错误] wgcf 配置生成失败。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    if [[ ! -f wgcf-profile.conf ]]; then
        red " [错误] 未生成 wgcf-profile.conf。"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    cp -f wgcf-profile.conf "$work_dir/${iface}.conf"

    # 强制替换为 CF 官方高可用 IP，解决 DNS 污染或无法握手的问题
    sed -i 's/engage.cloudflareclient.com/162.159.192.1/g' "$work_dir/${iface}.conf"

    # 强制注入 NAT 环境 UDP 心跳保活机制，防止断流
    if ! grep -q "PersistentKeepalive" "$work_dir/${iface}.conf"; then
        sed -i '/^Endpoint/a PersistentKeepalive = 15' "$work_dir/${iface}.conf"
    fi

    # 避免 wg-quick 自动接管系统默认路由
    if ! grep -q '^Table *= *off' "$work_dir/${iface}.conf"; then
        sed -i '/^\[Interface\]/a Table = off' "$work_dir/${iface}.conf"
    fi

    # 加 PostUp/PostDown，必须写入 [Interface] 段，不能追加到 [Peer] 后面
    sed -i '/^PostUp *=/d;/^PostDown *=/d' "$work_dir/${iface}.conf"

    awk -v mark="$mark" '
        /^\\[Peer\\]/ && !done {
            print "PostUp = ip -6 route replace default dev %i table " mark "; ip -6 rule add fwmark " mark " table " mark " 2>/dev/null || true"
            print "PostDown = ip -6 rule del fwmark " mark " table " mark " 2>/dev/null || true; ip -6 route flush table " mark " 2>/dev/null || true"
            done=1
        }
        { print }
    ' "$work_dir/${iface}.conf" > /tmp/wgcf.conf.fixed

    mv -f /tmp/wgcf.conf.fixed "$work_dir/${iface}.conf"

    chmod 600 "$work_dir/${iface}.conf"

    yellow " 正在启动 WARP IPv6 接口: $iface"

    wg-quick down "$iface" >/dev/null 2>&1 || true

    if ! wg-quick up "$iface"; then
        red " [错误] wg-quick up $iface 失败。"
        yellow " 可查看: cat $work_dir/${iface}.conf"
        rm -rf "$tmp_dir"
        sleep 2
        return
    fi

    if command -v systemctl >/dev/null 2>&1; then
        _smart_run "正在重载系统级守护进程配置" systemctl enable "wg-quick@${iface}"
    elif command -v rc-update >/dev/null 2>&1; then
        rc-update add wireguard default >/dev/null 2>&1 || true
    fi

    ip -6 route replace default dev "$iface" table "$mark" 2>/dev/null || true
    ip -6 rule add fwmark "$mark" table "$mark" 2>/dev/null || true

    green " [✔] WARP IPv6 接口已启动: $iface"

    if command -v curl >/dev/null 2>&1; then
        yellow " 正在测试 WARP IPv6 出口..."
        if curl -6 --interface "$iface" --connect-timeout 10 -fsSL https://www.cloudflare.com/cdn-cgi/trace >/tmp/warp-ipv6-trace.txt 2>/dev/null; then
            green " [✔] WARP IPv6 出口测试通过。"
            grep -E 'ip=|warp=' /tmp/warp-ipv6-trace.txt 2>/dev/null || true
        else
            yellow " [提示] 接口已启动，但 curl IPv6 测试失败。"
            yellow " 可稍后运行: curl -6 --interface $iface https://www.cloudflare.com/cdn-cgi/trace"
        fi
    fi

    rm -rf "$tmp_dir"

    echo ""
    yellow " 下一步：返回菜单选择 [1] 开启 / 修改 WARP IPv6 域名分流，接口名填写: $iface"
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回 WARP IPv6 分流菜单...${PLAIN}"
    read temp
}

warp_ipv6_route_menu() {
    while true; do
        clear
        print_line
        green " WARP IPv6 域名分流设置 "
        print_line
        echo ""

        show_warp_ipv6_status_panel

        if [[ ! -f /etc/sing-box/config.json ]]; then
            red " 未检测到 Sing-box 配置文件，请先安装节点。"
            sleep 2
            return
        fi

        local iface domains
        iface=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)
        domains=$(jq -r '.route.rules[]? | select(.outbound=="warp-ipv6") | .domain_suffix[]? // empty' /etc/sing-box/config.json 2>/dev/null | paste -sd "," -)

        if [[ -n "$iface" && "$iface" != "null" ]]; then
            green " 当前状态: [已开启]"
            yellow " WARP IPv6 接口: $iface"
            yellow " 分流域名: ${domains:-未读取到}"
        else
            yellow " 当前状态: [未开启]"
        fi

        echo ""
        printf "%b
" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}开启 / 修改 WARP IPv6 域名分流${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}关闭 WARP IPv6 域名分流${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}查看当前 WARP IPv6 分流规则${PLAIN}"
        printf "%b
" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_CYAN}安装 / 修复 WARP IPv6 接口 (wgcf)${PLAIN}"
        echo ""
        printf "%b
" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
        echo ""
        printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-6]: ${PLAIN}"
        read warp_ipv6_choice || return

        case "$warp_ipv6_choice" in
            1) enable_warp_ipv6_route ;;
            2) disable_warp_ipv6_route ;;
            3) show_warp_ipv6_route ;;
            4) install_or_repair_warp_ipv6_iface ;;
            0) return ;;
            *) red " 输入无效"; sleep 1 ;;
        esac
    done
}

enable_warp_ipv6_route() {
    clear
    print_line
    green " 开启 / 修改 WARP IPv6 域名分流 "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red " 未检测到 Sing-box 配置文件，请先安装节点。"
        sleep 2
        return
    fi

    local current_iface current_domains iface domains domains_json test_choice backup

    current_iface=$(jq -r '.outbounds[]? | select(.tag=="warp-ipv6") | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)
    [[ -z "$current_iface" || "$current_iface" == "null" ]] && current_iface="wgcf"

    current_domains=$(jq -r '.route.rules[]? | select(.outbound=="warp-ipv6") | .domain_suffix[]? // empty' /etc/sing-box/config.json 2>/dev/null | paste -sd "," -)
    [[ -z "$current_domains" ]] && current_domains="openai.com,chatgpt.com,oaistatic.com,oaiusercontent.com,anthropic.com,claude.ai,perplexity.ai,poe.com,gemini.google.com,aistudio.google.com,generativelanguage.googleapis.com"

    yellow " 本功能要求 VPS 已经有可用的 WARP IPv6 网络接口。"
    yellow " 常见接口名: wgcf / warp / CloudflareWARP"
    echo ""

    printf "%b" " ${LIGHT_YELLOW} ▶ WARP IPv6 接口名 [默认: $current_iface]: ${PLAIN}"
    read iface || return
    [[ -z "$iface" ]] && iface="$current_iface"

    if [[ ! "$iface" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
        red " [错误] 接口名格式不合法。"
        sleep 2
        return
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        red " [错误] 未检测到接口: $iface"
        yellow " 请先安装 / 启动 WARP，并确认 ip link 能看到该接口。"
        sleep 2
        return
    fi

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 分流域名，逗号分隔 [默认: $current_domains]: ${PLAIN}"
    read domains || return
    [[ -z "$domains" ]] && domains="$current_domains"

    domains="$(echo "$domains" | tr '，' ',' | tr -d '[:space:]')"

    domains_json=$(printf '%s' "$domains" | tr ',' '\n' | awk '
      BEGIN { print "["; first=1 }
      {
        gsub(/^\.+/, "", $0)
        if ($0 == "") next
        if ($0 !~ /^[A-Za-z0-9.-]+$/) exit 2
        if (!first) printf ","
        printf "\"%s\"", $0
        first=0
      }
      END { print "]" }
    ')

    if [[ $? -ne 0 || -z "$domains_json" || "$domains_json" == "[]" ]]; then
        red " [错误] 域名列表格式不合法。"
        sleep 2
        return
    fi

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 是否测试该接口 IPv6 出口？(y/n) [默认: y]: ${PLAIN}"
    read test_choice || test_choice="y"
    [[ -z "$test_choice" ]] && test_choice="y"

    if [[ "$test_choice" == "y" || "$test_choice" == "Y" ]]; then
        if command -v curl >/dev/null 2>&1; then
            yellow " 正在测试 WARP IPv6 出口..."
            if curl -6 --interface "$iface" --connect-timeout 8 -fsSL https://www.cloudflare.com/cdn-cgi/trace >/tmp/warp-ipv6-trace.txt 2>/dev/null; then
                green " [✔] WARP IPv6 出口测试通过。"
                grep -E 'ip=|warp=' /tmp/warp-ipv6-trace.txt 2>/dev/null || true
            else
                red " [错误] WARP IPv6 出口测试失败。"
                yellow " 请确认该接口具备 IPv6 出口能力。"
                sleep 2
                return
            fi
        else
            yellow " 未检测到 curl，跳过 IPv6 出口测试。"
        fi
    fi

    backup="/etc/sing-box/config.json.bak.warp-ipv6.$(date +%F-%H%M%S)"
    cp -a /etc/sing-box/config.json "$backup"

    jq --arg iface "$iface" --argjson domains "$domains_json" '
      .outbounds = ((.outbounds // []) | map(select(.tag != "warp-ipv6")))
      | .outbounds += [
          {
            "type": "direct",
            "tag": "warp-ipv6",
            "bind_interface": $iface,
            "routing_mark": 51820,
            "domain_strategy": "ipv6_only"
          }
        ]
      | .route = (.route // {})
      | .route.rules = (
          [
            {
              "domain_suffix": $domains,
              "outbound": "warp-ipv6"
            }
          ]
          + ((.route.rules // []) | map(select(.outbound != "warp-ipv6")))
        )
    ' /etc/sing-box/config.json > /tmp/sb_warp_ipv6.json

    if [[ $? -ne 0 || ! -s /tmp/sb_warp_ipv6.json ]]; then
        red " [错误] jq 写入 WARP IPv6 分流配置失败。"
        mv -f "$backup" /etc/sing-box/config.json
        sleep 2
        return
    fi

    mv -f /tmp/sb_warp_ipv6.json /etc/sing-box/config.json
    chmod 600 /etc/sing-box/config.json 2>/dev/null || true

    if [[ -x /usr/local/bin/sing-box ]]; then
        if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
            red " [错误] sing-box 配置校验失败，正在回滚。"
            mv -f "$backup" /etc/sing-box/config.json
            restart_singbox_checked || true
            sleep 2
            return
        fi
    fi

    restart_singbox_checked || {
        red " [错误] sing-box 重启失败，正在回滚。"
        mv -f "$backup" /etc/sing-box/config.json
        restart_singbox_checked || true
        sleep 2
        return
    }

    green " [✔] WARP IPv6 域名分流已开启。"
    yellow " 接口: $iface"
    yellow " 域名: $domains"

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回 WARP IPv6 分流菜单...${PLAIN}"
    read temp
}

disable_warp_ipv6_route() {
    clear
    print_line
    green " 关闭 WARP IPv6 域名分流 "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red " 未检测到 Sing-box 配置文件。"
        sleep 2
        return
    fi

    local backup
    backup="/etc/sing-box/config.json.bak.disable-warp-ipv6.$(date +%F-%H%M%S)"
    cp -a /etc/sing-box/config.json "$backup"

    jq '
      .outbounds = ((.outbounds // []) | map(select(.tag != "warp-ipv6")))
      | .route.rules = ((.route.rules // []) | map(select(.outbound != "warp-ipv6")))
    ' /etc/sing-box/config.json > /tmp/sb_disable_warp_ipv6.json

    if [[ $? -ne 0 || ! -s /tmp/sb_disable_warp_ipv6.json ]]; then
        red " [错误] jq 清理 WARP IPv6 分流配置失败。"
        mv -f "$backup" /etc/sing-box/config.json
        sleep 2
        return
    fi

    mv -f /tmp/sb_disable_warp_ipv6.json /etc/sing-box/config.json
    chmod 600 /etc/sing-box/config.json 2>/dev/null || true

    if [[ -x /usr/local/bin/sing-box ]]; then
        if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
            red " [错误] 清理后配置校验失败，正在回滚。"
            mv -f "$backup" /etc/sing-box/config.json
            restart_singbox_checked || true
            sleep 2
            return
        fi
    fi

    restart_singbox_checked || {
        red " [错误] sing-box 重启失败，正在回滚。"
        mv -f "$backup" /etc/sing-box/config.json
        restart_singbox_checked || true
        sleep 2
        return
    }

    green " [✔] WARP IPv6 域名分流已关闭。"

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回 WARP IPv6 分流菜单...${PLAIN}"
    read temp
}

show_warp_ipv6_route() {
    clear
    print_line
    green " 当前 WARP IPv6 域名分流规则 "
    print_line
    echo ""

    if [[ ! -f /etc/sing-box/config.json ]]; then
        red " 未检测到 Sing-box 配置文件。"
        sleep 2
        return
    fi

    yellow " WARP IPv6 出站:"
    jq '.outbounds[]? | select(.tag=="warp-ipv6")' /etc/sing-box/config.json 2>/dev/null || true

    echo ""
    yellow " WARP IPv6 分流规则:"
    jq '.route.rules[]? | select(.outbound=="warp-ipv6")' /etc/sing-box/config.json 2>/dev/null || true

    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 按回车键返回 WARP IPv6 分流菜单...${PLAIN}"
    read temp
}








