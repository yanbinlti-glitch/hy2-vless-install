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
#  3. 服务管理与标签化防火墙管控
# =================================================================
svc_start()   { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" start; else systemctl start "$1"; fi; }
svc_stop()    { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" stop; else systemctl stop "$1"; fi; }
svc_restart() { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" restart; else systemctl restart "$1"; fi; }
svc_enable()  { if [[ $SYSTEM == "Alpine" ]]; then rc-update add "$1" default; else systemctl enable "$1"; fi; }
svc_disable() { if [[ $SYSTEM == "Alpine" ]]; then rc-update del "$1" default; else systemctl disable "$1"; fi; }

is_svc_active() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service "$1" status 2>/dev/null | grep -q 'started'
    else
        systemctl is-active --quiet "$1" 2>/dev/null
    fi
}

save_iptables() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service iptables save
        rc-service ip6tables save
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
        service iptables save
        service ip6tables save
    else
        if command -v netfilter-persistent >/dev/null; then
            netfilter-persistent save
        fi
    fi
}

open_port() {
    local port=$1
    local proto=$2
    local tag=$3
    mkdir -p /etc/sing-box

    # 防止重复写入状态文件，避免多次运行脚本后防火墙状态膨胀。
    touch /etc/sing-box/.firewall_state
    if ! grep -qxF "$tag:$proto:$port" /etc/sing-box/.firewall_state 2>/dev/null; then
        echo "$tag:$proto:$port" >> /etc/sing-box/.firewall_state
    fi
    
    yellow " [防火墙] 正在放行 $proto 端口 $port..."
    if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --add-port=$port/$proto --permanent
        firewall-cmd --reload
    elif command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $port/$proto
    else
        if iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
            green " [防火墙] IPv4 $proto 端口 $port 已存在放行规则。"
        else
            iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
        fi
        if command -v ip6tables >/dev/null 2>&1; then
            if ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
                green " [防火墙] IPv6 $proto 端口 $port 已存在放行规则。"
            else
                ip6tables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
            fi
        fi
        save_iptables
    fi
}
close_port_by_tag() {
    local target_tag=$1
    if [[ -f /etc/sing-box/.firewall_state ]]; then
        local tmp_state=$(mktemp)
        while IFS=: read -r tag proto port; do
            if [[ "$tag" == "$target_tag" ]]; then
                yellow " [防火墙] 正在移除 $proto 端口 $port 的放行规则..."
                iptables-save | grep -v -- "-p $proto -m $proto --dport $port -j ACCEPT" | iptables-restore
                ip6tables-save | grep -v -- "-p $proto -m $proto --dport $port -j ACCEPT" | ip6tables-restore
                if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
                    firewall-cmd --remove-port=$port/$proto --permanent
                    firewall-cmd --reload
                fi
                if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
                    ufw delete allow $port/$proto
                fi
            else
                echo "$tag:$proto:$port" >> "$tmp_state"
            fi
        done < /etc/sing-box/.firewall_state
        mv "$tmp_state" /etc/sing-box/.firewall_state
    fi
    save_iptables
}

