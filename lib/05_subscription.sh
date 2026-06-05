#!/usr/bin/env bash
# shellcheck shell=bash

#  6. 核心业务处理与多态聚合订阅引擎 (完全修复 YAML 换行 Bug)
# =================================================================
generate_client_configs() {
    realip
    check_installed_nodes
    
    if [[ $has_hy2 -eq 0 && $has_vless -eq 0 ]]; then
        return
    fi

    local sub_port=$(cat /etc/sing-box/sub_port.txt 2>/dev/null | LC_ALL=C tr -dc '0-9')
    if [[ -z "$sub_port" ]]; then
        yellow "  [订阅修复] 未检测到订阅端口，正在自动生成新的订阅端口..."
        sub_port=$(shuf -i 10000-30000 -n 1)
        while ss -tnl 2>/dev/null | grep -E -q "(:|^)$sub_port( |$)"; do
            sub_port=$(shuf -i 10000-30000 -n 1)
        done
        echo "$sub_port" > /etc/sing-box/sub_port.txt
        open_port "$sub_port" "tcp" "sub"
    fi

    local sub_uuid=$(cat /root/.hy2_sub_uuid 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9')
    [[ -z "$sub_uuid" ]] && sub_uuid=$(echo "${PUBLIC_IP}-Singbox-Sub" | md5sum | head -c 16)
    echo "$sub_uuid" > /root/.hy2_sub_uuid
    echo "$sub_uuid" > /etc/sing-box/sub_path.txt
    
    local web_dir="/var/www/sing-box"
    mkdir -p "$web_dir/$sub_uuid"
    
    local url_all=""
    local proxy_yaml=""
    local proxy_names=""
    local sb_outbounds=""
    local sb_tags=""

    local yaml_json_ip="$PUBLIC_IP"
    local uri_ip="$PUBLIC_IP"
    [[ "$PUBLIC_IP" == *":"* ]] && uri_ip="[$PUBLIC_IP]"

    # ================= 聚合: Hysteria 2 =================
    if [[ $has_hy2 -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/hy2_name.txt 2>/dev/null || echo "Hy2_Node")
        local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
        local bind_port=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' /etc/sing-box/config.json)
        local hop_ports=$(cat /etc/sing-box/hy2_hop_ports.txt 2>/dev/null | tr -d '[:space:]')
        [[ ! "$hop_ports" =~ ^[0-9]+-[0-9]+$ ]] && hop_ports=""
        # 通用 hysteria2:// URI 使用主监听端口，避免部分客户端/订阅转换器无法解析端口范围。
        # Clash/Mihomo 与 sing-box 专用订阅仍分别通过 ports / server_ports 保留端口跳跃。
        local hy2_client_port="$bind_port"
        local pwd=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' /etc/sing-box/config.json)
        local sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.bing.com")
        local obfs=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .obfs?.password // empty' /etc/sing-box/config.json)

        local cert_pin=$(openssl x509 -in /etc/sing-box/cert.crt -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)
        local spki_pin=$(openssl x509 -in /etc/sing-box/cert.crt -noout -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)

        local s_pwd=$(PWD="$pwd" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('PWD', '')))")
        local url="hysteria2://$s_pwd@$uri_ip:$hy2_client_port/?insecure=1&pinSHA256=$cert_pin&sni=$sni"
        [[ -n "$hop_ports" ]] && url="${url}&mport=${hop_ports}"
        [[ -n "$obfs" ]] && url="${url}&obfs=salamander&obfs-password=${obfs}"
        url="${url}#${safe_node_name}"
        
        # 修复 Bug 1：使用标准 Bash 物理换行，防止写死字面量 \n
        url_all="${url_all}${url}
"

        proxy_yaml="${proxy_yaml}
  - name: '${node_name}'
    type: hysteria2
    udp: true
    server: \"$yaml_json_ip\"
    port: $bind_port
    $(if [[ -n "$hop_ports" ]]; then printf 'ports: "%s"' "$hop_ports"; fi)
    password: '${pwd}'
    sni: \"$sni\"
    skip-cert-verify: true
    alpn:
      - h3"
        [[ -n "$obfs" ]] && proxy_yaml="${proxy_yaml}
    obfs: salamander
    obfs-password: \"$obfs\""
        
        # 修复 Bug 2：防止 YAML 数组解析报错
        proxy_names="${proxy_names}
      - '${node_name}'"
        
        local sb_hy2_port_json="\"server_port\":${bind_port}"
        [[ -n "$hop_ports" ]] && sb_hy2_port_json="\"server_port\":${bind_port},\"server_ports\":[\"${hop_ports}\"]"
        local sb_hy2_json="{\"type\":\"hysteria2\",\"tag\":\"${node_name}\",\"server\":\"${yaml_json_ip}\",${sb_hy2_port_json},\"password\":\"${pwd}\",\"tls\":{\"enabled\":true,\"server_name\":\"${sni}\",\"insecure\":true,\"certificate_public_key_sha256\":[\"${spki_pin}\"],\"alpn\":[\"h3\"]}"
        [[ -n "$obfs" ]] && sb_hy2_json="${sb_hy2_json},\"obfs\":{\"type\":\"salamander\",\"password\":\"${obfs}\"}"
        sb_hy2_json="${sb_hy2_json}}"
        
        sb_outbounds="${sb_outbounds}${sb_hy2_json},"
        sb_tags="${sb_tags}\"${node_name}\","
    fi

    # ================= 聚合: VLESS =================
    if [[ $has_vless -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/vless_name.txt 2>/dev/null || echo "Vless_Node")
        local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
        local bind_port=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .listen_port' /etc/sing-box/config.json)
        local uuid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .users[0].uuid' /etc/sing-box/config.json)
        local sni=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.server_name // empty' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$sni" || "$sni" == "null" ]] && sni=$(cat /etc/sing-box/vless_sni.txt 2>/dev/null || cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.microsoft.com")
        local pub=$(cat /etc/sing-box/reality_pub.txt 2>/dev/null)
        local sid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.reality.short_id[0]' /etc/sing-box/config.json)

        local url="vless://$uuid@$uri_ip:$bind_port/?security=reality&encryption=none&pbk=$pub&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$sni&sid=$sid#${safe_node_name}"
        
        url_all="${url_all}${url}
"

        proxy_yaml="${proxy_yaml}
  - name: '${node_name}'
    type: vless
    server: \"$yaml_json_ip\"
    port: $bind_port
    uuid: \"$uuid\"
    network: tcp
    tls: true
    udp: true
    xudp: true
    flow: xtls-rprx-vision
    servername: \"$sni\"
    client-fingerprint: chrome
    reality-opts:
      public-key: \"$pub\"
      short-id: \"$sid\""
        
        proxy_names="${proxy_names}
      - '${node_name}'"
        
        local sb_vless_json="{\"type\":\"vless\",\"tag\":\"${node_name}\",\"server\":\"${yaml_json_ip}\",\"server_port\":${bind_port},\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"packet_encoding\":\"xudp\",\"tcp_fast_open\":true,\"tls\":{\"enabled\":true,\"server_name\":\"${sni}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${pub}\",\"short_id\":\"${sid}\"}}}"
        sb_outbounds="${sb_outbounds}${sb_vless_json},"
        sb_tags="${sb_tags}\"${node_name}\","
    fi

    sb_outbounds="${sb_outbounds%,}"
    sb_tags="${sb_tags%,}"

    # 修复 Bug 3：正确输出文本流
    printf "%s" "$url_all" > "$web_dir/$sub_uuid/url.txt"
    printf "%s" "$url_all" | base64 -w 0 2>/dev/null > "$web_dir/$sub_uuid/sub_b64.txt" || printf "%s" "$url_all" | base64 | tr -d '\r\n' > "$web_dir/$sub_uuid/sub_b64.txt"

    local sub_url="http://${PUBLIC_IP}:${sub_port}/${sub_uuid}"
    [[ "$PUBLIC_IP" == *":"* ]] && sub_url="http://[${PUBLIC_IP}]:${sub_port}/${sub_uuid}"
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -o "$web_dir/$sub_uuid/sub_qr.png" -s 8 -m 2 "$sub_url" || true
        qrencode -t ANSIUTF8 "$sub_url" > "$web_dir/$sub_uuid/sub_qr.txt" || true
    fi
    
    cat << EOF > "$web_dir/$sub_uuid/clash-meta-sub.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: true
proxies:$proxy_yaml
proxy-groups:
  - name: "节点选择"
    type: select
    proxies:$proxy_names
      - DIRECT
rules:
$([[ "$yaml_json_ip" == *":"* ]] && echo "  - IP-CIDR6,$yaml_json_ip/128,DIRECT,no-resolve" || echo "  - IP-CIDR,$yaml_json_ip/32,DIRECT,no-resolve")
  - DST-PORT,$sub_port,DIRECT
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
EOF

    cat << EOF > "$web_dir/$sub_uuid/sing-box.json"
{
  "outbounds": [
    { "type": "selector", "tag": "Proxy", "outbounds": ["Auto", $sb_tags] },
    { "type": "urltest", "tag": "Auto", "outbounds": [$sb_tags] },
    $sb_outbounds,
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" },
    { "type": "dns", "tag": "dns-out" }
  ]
}
EOF

    chown -R www-data:www-data "$web_dir" 2>/dev/null || chown -R nginx:nginx "$web_dir" 2>/dev/null
    chmod -R 750 "$web_dir"

    local nginx_conf_file="/etc/nginx/conf.d/sing-box-sub.conf"
    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
        nginx_conf_file="/etc/nginx/sites-available/sing-box-sub.conf"
    elif [[ $SYSTEM == "Alpine" ]]; then
        mkdir -p /etc/nginx/http.d
        nginx_conf_file="/etc/nginx/http.d/sing-box-sub.conf"
    else
        mkdir -p /etc/nginx/conf.d
    fi
    
    local listen_ipv6=""
    [[ -f /proc/net/if_inet6 ]] && listen_ipv6="listen [::]:$sub_port;"

    cat << EOF > "$nginx_conf_file"
server {
    listen $sub_port;
    $listen_ipv6
    
    root $web_dir;

    location = /$sub_uuid {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
        if (\$http_user_agent ~* "(clash|meta|verge|stash|mihomo)") { rewrite ^ /$sub_uuid/clash-meta-sub.yaml last; }
        if (\$http_user_agent ~* "(sing-box|sfa|sfi|sfm)") { rewrite ^ /$sub_uuid/sing-box.json last; }
        rewrite ^ /$sub_uuid/sub_b64.txt last;
    }

    location ~ ^/$sub_uuid/(clash-meta-sub\.yaml|sing-box\.json|sub_b64\.txt|url\.txt|sub_qr\.txt)$ {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
    }

    location = /$sub_uuid/sub_qr.png {
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
    }

    location / { return 403; }
}
EOF

    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        ln -sf /etc/nginx/sites-available/sing-box-sub.conf /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi

    yellow "  正在执行 Nginx 配置校验，完整输出如下："
    if nginx -t; then
        svc_enable nginx
        if is_svc_active nginx; then
            if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx reload; else systemctl reload nginx; fi
        else
            if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx start; else systemctl start nginx; fi
        fi
    else
        red "  [警告] Nginx 语法测试失败，请检查端口是否冲突！"
    fi
}

clean_env() {
    local mode="$1"
    if command -v disable_hy2_port_hopping >/dev/null 2>&1; then
        disable_hy2_port_hopping "quiet" || true
    fi
    close_port_by_tag "hy2-in"
    close_port_by_tag "vless-in"
    close_port_by_tag "sub"

    svc_stop sing-box
    svc_disable sing-box
    
    rm -f /etc/nginx/conf.d/sing-box-sub.conf /etc/nginx/sites-available/sing-box-sub.conf /etc/nginx/sites-enabled/sing-box-sub.conf /etc/nginx/http.d/sing-box-sub.conf
    if is_svc_active nginx; then
        if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx reload; else systemctl reload nginx; fi
    fi

    if [[ $SYSTEM == "Alpine" ]]; then
        rm -f /etc/init.d/sing-box
    else
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
    fi
    save_iptables

    rm -rf /etc/sing-box /var/www/sing-box
    if [[ "$mode" == "all" ]]; then
        rm -f /usr/local/bin/sing-box
        rm -f /usr/bin/666 /usr/bin/hy2
    fi
}

