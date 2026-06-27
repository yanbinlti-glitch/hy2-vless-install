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
#  6. 核心业务处理与多态聚合订阅引擎 (完全修复 YAML 换行 Bug)
# =================================================================
_uri_encode() {
  local value="${1-}"

  jq -rn \
    --arg value "$value" \
    '$value | @uri'
}

generate_client_configs() {
    realip
    check_installed_nodes
    
    if [[ $has_hy2 -eq 0 && $has_vless -eq 0 && $has_tuic -eq 0 ]]; then
        return
    fi

    local sub_port=$(cat /etc/sing-box/sub_port${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null | LC_ALL=C tr -dc '0-9')
    if [[ -z "$sub_port" ]]; then
        yellow "  [订阅修复] 未检测到订阅端口，正在自动生成新的订阅端口..."
        sub_port=$(shuf -i 10000-30000 -n 1)
        while ss -tnl 2>/dev/null | grep -E -q "(:|^)$sub_port( |$)"; do
            sub_port=$(shuf -i 10000-30000 -n 1)
        done
        printf "%s\n" "$sub_port" > /etc/sing-box/sub_port${HY2_INSTANCE_SUFFIX}.txt.tmp && mv -f /etc/sing-box/sub_port${HY2_INSTANCE_SUFFIX}.txt.tmp /etc/sing-box/sub_port${HY2_INSTANCE_SUFFIX}.txt
        open_port "$sub_port" "tcp" "sub"
    fi

    local token_file="/root/.hy2_sub_uuid${HY2_INSTANCE_SUFFIX}"
  local old_sub_uuid=""
  local sub_uuid=""
  local token_tmp=""

  old_sub_uuid=$(
    cat "$token_file" 2>/dev/null |
      LC_ALL=C tr -dc 'a-zA-Z0-9' || true
  )

  # 仅保留已经符合新规范的 256 位随机令牌。
  if [[ "$old_sub_uuid" =~ ^[0-9a-f]{64}$ ]]; then
    sub_uuid="$old_sub_uuid"
  else
    if command -v openssl >/dev/null 2>&1; then
      sub_uuid=$(openssl rand -hex 32)
    else
      sub_uuid=$(
        od -An -N32 -tx1 /dev/urandom |
          tr -d ' \n'
      )
    fi

    if [[ ! "$sub_uuid" =~ ^[0-9a-f]{64}$ ]]; then
      red " [错误] 无法生成安全的订阅令牌。"
      return 1
    fi

    # 旧令牌可预测，轮换后删除旧订阅目录，
    # 使旧订阅链接立即失效。
    if [[ -n "$old_sub_uuid" &&
          "$old_sub_uuid" =~ ^[A-Za-z0-9]{1,128}$ ]]
    then
      rm -rf -- "/var/www/sing-box${HY2_INSTANCE_SUFFIX}/$old_sub_uuid"
    fi
  fi

  # 在 root 私有目录中原子保存令牌。
  token_tmp=$(
    mktemp /root/.hy2_sub_uuid${HY2_INSTANCE_SUFFIX}.tmp.XXXXXX
  ) || return 1

  printf '%s\n' "$sub_uuid" > "$token_tmp"
  chmod 600 "$token_tmp"

  if ! mv -f "$token_tmp" "$token_file"; then
    rm -f "$token_tmp"
    red " [错误] 无法保存订阅令牌。"
    return 1
  fi

  install -d -m 700 /etc/sing-box

  printf '%s\n' "$sub_uuid" \
    > /etc/sing-box/sub_path${HY2_INSTANCE_SUFFIX}.txt

  chmod 600 /etc/sing-box/sub_path${HY2_INSTANCE_SUFFIX}.txt

  local web_dir="/var/www/sing-box${HY2_INSTANCE_SUFFIX}"

  install -d -m 750 \
    "$web_dir/$sub_uuid"
    
    local url_all=""
    local proxy_yaml=""
    local proxy_names=""
    local sb_outbounds='[]'
    local sb_tags='[]'

    local yaml_json_ip="$(get_sub_ip)"
    local uri_ip="$(get_sub_ip)"
    [[ "$(get_sub_ip)" == *":"* ]] && uri_ip="[$(get_sub_ip)]"

    # ================= 聚合: Hysteria 2 =================
    if [[ $has_hy2 -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/hy2_name${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "Hy2_Node")
        local yaml_node_name="${node_name//\'/\'\'}"
        local safe_node_name=$(jq -nr --arg v "$node_name" '$v|@uri')
        local bind_port=""
        local pwd=""
        local obfs=""

        bind_port=$(jq -er '[.inbounds[]? | select(.tag=="hy2-in") | (.listen_port // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || bind_port=""
        pwd=$(jq -er '[.inbounds[]? | select(.tag=="hy2-in") | (.users[0].password // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || pwd=""
        obfs=$(jq -r '[.inbounds[]? | select(.tag=="hy2-in") | (.obfs.password // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || obfs=""

        if [[ ! "$bind_port" =~ ^[0-9]+$ || -z "$pwd" ]]; then
            red " [错误] Hysteria2 节点参数读取失败，无法生成客户端 JSON。"
            jq -r '.inbounds[]? | " tag=\(.tag // "") type=\(.type // "") listen_port=\(.listen_port // "")"' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null || true
            return 1
        fi
        local hop_ports=$(cat /etc/sing-box/hy2_hop_ports${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null | tr -d '[:space:]')
        [[ ! "$hop_ports" =~ ^[0-9]+-[0-9]+$ ]] && hop_ports=""
        # 通用 hysteria2:// URI 使用主监听端口，避免部分客户端/订阅转换器无法解析端口范围。
        # Clash/Mihomo 与 sing-box 专用订阅仍分别通过 ports / server_ports 保留端口跳跃。
        local hy2_client_port="$bind_port"
        local sni=$(jq -r '[.inbounds[]? | select(.tag=="hy2-in") | (.tls.server_name // empty) | tostring] | first // ""' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$sni" || "$sni" == "null" ]] && sni=$(cat /etc/sing-box/hy2_sni.txt 2>/dev/null || cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.bing.com")

        local cert_path=$(jq -r '[.inbounds[]? | select(.tag=="hy2-in") | (.tls.certificate_path // empty) | tostring] | first // ""' /etc/sing-box/config.json 2>/dev/null)
        [[ -z "$cert_path" || "$cert_path" == "null" ]] && cert_path="/etc/sing-box/hy2.crt"
        [[ ! -f "$cert_path" ]] && cert_path="/etc/sing-box/cert.crt"

        local cert_pin=$(openssl x509 -in "$cert_path" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d :)
        local spki_pin=$(openssl x509 -in "$cert_path" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64)

        local yaml_pwd="${pwd//\'/\'\'}"
        local s_pwd=$(jq -nr --arg v "$pwd" '$v|@uri')
  local s_sni=""
  local s_cert_pin=""
  local s_hop_ports=""
  local s_obfs=""

  s_sni="$(_uri_encode "$sni")" ||
    return 1

  s_cert_pin="$(_uri_encode "$cert_pin")" ||
    return 1

  if [[ -n "$hop_ports" ]]; then
    s_hop_ports="$(_uri_encode "$hop_ports")" ||
      return 1
  fi

  if [[ -n "$obfs" ]]; then
    s_obfs="$(_uri_encode "$obfs")" ||
      return 1
  fi
        local url="hysteria2://$s_pwd@$(get_link_ip):$hy2_client_port/?insecure=1&pinSHA256=$s_cert_pin&sni=$s_sni"
        [[ -n "$hop_ports" ]] && url="${url}&mport=${s_hop_ports}"
        [[ -n "$obfs" ]] && url="${url}&obfs=salamander&obfs-password=${s_obfs}"
        url="${url}#${safe_node_name}"
        
        # 修复 Bug 1：使用标准 Bash 物理换行，防止写死字面量 \n
        url_all="${url_all}${url}
"

        proxy_yaml="${proxy_yaml}
  - name: '${yaml_node_name}'
    type: hysteria2
    udp: true
    server: \"$yaml_json_ip\"
    port: $bind_port
    $(if [[ -n "$hop_ports" ]]; then printf 'ports: "%s"' "$hop_ports"; fi)
    password: '${yaml_pwd}'
    sni: \"$sni\"
    skip-cert-verify: true
    alpn:
      - h3"
        [[ -n "$obfs" ]] && proxy_yaml="${proxy_yaml}
    obfs: salamander
    obfs-password: \"$obfs\""
        
        # 修复 Bug 2：防止 YAML 数组解析报错
        proxy_names="${proxy_names}
      - '${yaml_node_name}'"
        

        local sb_hy2_json=""

        if ! sb_hy2_json=$(
          jq -cn \
            --arg tag "$node_name" \
            --arg server "$yaml_json_ip" \
            --arg port "$bind_port" \
            --arg hop_ports "$hop_ports" \
            --arg password "$pwd" \
            --arg sni "$sni" \
            --arg spki_pin "$spki_pin" \
            --arg obfs "$obfs" \
            '
              {
                type: "hysteria2",
                tag: $tag,
                server: \"$server\",
                server_port: ($port | tonumber),
                password: \"$password\",
                tls: {
                  enabled: true,
                  server_name: \"$sni\",
                  insecure: true,
                  certificate_public_key_sha256: [
                    $spki_pin
                  ],
                  alpn: ["h3"]
                }
              }
              + (
                if $hop_ports != ""
                then {
                  server_ports: ($hop_ports | split(",") | map(select(length > 0)))
                }
                else {}
                end
              )
              + (
                if $obfs != ""
                then {
                  obfs: {
                    type: "salamander",
                    password: \"$obfs\"
                  }
                }
                else {}
                end
              )
            '
        ); then
          red " [错误] 无法生成 Hysteria2 客户端 JSON。"
          return 1
        fi

        if ! sb_outbounds=$(
          jq -cn \
            --argjson current "$sb_outbounds" \
            --argjson item "$sb_hy2_json" \
            '$current + [$item]'
        ); then
          red " [错误] 无法聚合 Hysteria2 客户端配置。"
          return 1
        fi

        if ! sb_tags=$(
          jq -cn \
            --argjson current "$sb_tags" \
            --arg tag "$node_name" \
            '$current + [$tag]'
        ); then
          red " [错误] 无法聚合 Hysteria2 节点标签。"
          return 1
        fi
    fi

    # ================= 聚合: VLESS =================
    if [[ $has_vless -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/vless_name${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "Vless_Node")
        local yaml_node_name="${node_name//\'/\'\'}"
        local safe_node_name=$(jq -nr --arg v "$node_name" '$v|@uri')
        local bind_port=""
        local uuid=""
        local sni=""
        local sid=""

        bind_port=$(jq -er '[.inbounds[]? | select(.tag=="vless-in") | (.listen_port // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || bind_port=""
        uuid=$(jq -er '[.inbounds[]? | select(.tag=="vless-in") | (.users[0].uuid // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || uuid=""
        sni=$(jq -r '[.inbounds[]? | select(.tag=="vless-in") | (.tls.server_name // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || sni=""
        sid=$(jq -er '[.inbounds[]? | select(.tag=="vless-in") | (.tls.reality.short_id[0] // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || sid=""

        if [[ ! "$bind_port" =~ ^[0-9]+$ || -z "$uuid" || -z "$sid" ]]; then
            red " [错误] VLESS 节点参数读取失败，无法生成客户端 JSON。"
            jq -r '.inbounds[]? | " tag=\(.tag // "") type=\(.type // "") listen_port=\(.listen_port // "")"' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null || true
            return 1
        fi
        [[ -z "$sni" || "$sni" == "null" ]] && sni=$(cat /etc/sing-box/vless_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "www.microsoft.com")
        local pub=$(cat /etc/sing-box/reality_pub${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null)
  local s_reality_pub=""
  local s_vless_sni=""
  local s_reality_sid=""

  s_reality_pub="$(_uri_encode "$pub")" ||
    return 1

  s_vless_sni="$(_uri_encode "$sni")" ||
    return 1

  s_reality_sid="$(_uri_encode "$sid")" ||
    return 1

        local url="vless://$uuid@$(get_link_ip):$bind_port/?security=reality&encryption=none&pbk=$s_reality_pub&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$s_vless_sni&sid=$s_reality_sid#${safe_node_name}"
        
        url_all="${url_all}${url}
"

        proxy_yaml="${proxy_yaml}
  - name: '${yaml_node_name}'
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
      - '${yaml_node_name}'"
        

        local sb_vless_json=""

        if ! sb_vless_json=$(
          jq -cn \
            --arg tag "$node_name" \
            --arg server "$yaml_json_ip" \
            --arg port "$bind_port" \
            --arg uuid "$uuid" \
            --arg sni "$sni" \
            --arg public_key "$pub" \
            --arg short_id "$sid" \
            '
              {
                type: "vless",
                tag: $tag,
                server: \"$server\",
                server_port: ($port | tonumber),
                uuid: \"$uuid\",
                flow: "xtls-rprx-vision",
                packet_encoding: "xudp",
                tcp_fast_open: true,
                tls: {
                  enabled: true,
                  server_name: \"$sni\",
                  utls: {
                    enabled: true,
                    fingerprint: "chrome"
                  },
                  reality: {
                    enabled: true,
                    public_key: $public_key,
                    short_id: $short_id
                  }
                }
              }
            '
        ); then
          red " [错误] 无法生成 VLESS 客户端 JSON。"
          return 1
        fi

        if ! sb_outbounds=$(
          jq -cn \
            --argjson current "$sb_outbounds" \
            --argjson item "$sb_vless_json" \
            '$current + [$item]'
        ); then
          red " [错误] 无法聚合 VLESS 客户端配置。"
          return 1
        fi

        if ! sb_tags=$(
          jq -cn \
            --argjson current "$sb_tags" \
            --arg tag "$node_name" \
            '$current + [$tag]'
        ); then
          red " [错误] 无法聚合 VLESS 节点标签。"
          return 1
        fi
    fi



    # ================= 聚合: TUIC =================
    if [[ $has_tuic -eq 1 ]]; then
        local node_name=$(cat /etc/sing-box/tuic_name${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "TUIC_Node")
        node_name="${node_name//$'\r'/}"
        node_name="${node_name//$'\n'/}"
        node_name="${node_name//\\r/}"
        node_name="${node_name//\\n/}"
        [[ -z "$node_name" || "$node_name" == "-1" || "$node_name" == "null" || "$node_name" == "NULL" ]] && node_name="TUIC_Node"
        [[ -z "$node_name" || "$node_name" == "-1" || "$node_name" == "null" || "$node_name" == "NULL" ]] && node_name="TUIC_Node"
        local yaml_node_name="${node_name//\'/\'\'}"
        local safe_node_name=$(jq -nr --arg v "$node_name" '$v|@uri')
        local bind_port uuid pwd sni

        bind_port=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.listen_port // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || bind_port=""
        uuid=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.users[0].uuid // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || uuid=""
        pwd=$(jq -er '[.inbounds[]? | select(.tag=="tuic-in") | (.users[0].password // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || pwd=""
        sni=$(jq -r '[.inbounds[]? | select(.tag=="tuic-in") | (.tls.server_name // empty) | tostring] | first // ""' /etc/sing-box/config${HY2_INSTANCE_SUFFIX}.json 2>/dev/null) || sni=""
        [[ -z "$sni" || "$sni" == "-1" || "$sni" == "null" || "$sni" == "NULL" ]] && sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "www.bing.com")
        [[ -z "$sni" || "$sni" == "null" ]] && sni=$(cat /etc/sing-box/cert_sni${HY2_INSTANCE_SUFFIX}.txt 2>/dev/null || echo "www.bing.com")

        if [[ -n "$bind_port" && -n "$uuid" && -n "$pwd" ]]; then
            local s_uuid="$(_uri_encode "$uuid")"
            local s_pwd="$(_uri_encode "$pwd")"
            local s_sni="$(_uri_encode "$sni")"
            
            local url="tuic://${s_uuid}:${s_pwd}@$(get_link_ip):${bind_port}/?sni=${s_sni}&alpn=h3&congestion_control=bbr&insecure=1&allow_insecure=1#${safe_node_name}"
            url_all="${url_all}${url}"$'
'

            proxy_yaml="${proxy_yaml}\n  - name: '${yaml_node_name}'\n    type: tuic\n    server: \"$yaml_json_ip\"\n    port: $bind_port\n    uuid: \"$uuid\"\n    password: \"$pwd\"\n    sni: \"$sni\"\n    alpn: [h3]\n    skip-cert-verify: true\n    reduce-rtt: true\n    udp-relay-mode: native"
            proxy_names="${proxy_names}\n      - '${yaml_node_name}'"

            local sb_tuic_json=$(jq -cn \
                --arg tag "$node_name" \
                --arg server "$yaml_json_ip" \
                --arg port "$bind_port" \
                --arg uuid "$uuid" \
                --arg password "$pwd" \
                --arg sni "$sni" \
                '{
                    type: "tuic",
                    tag: $tag,
                    server: \"$server\",
                    server_port: ($port | tonumber),
                    uuid: \"$uuid\",
                    password: \"$password\",
                    congestion_control: "bbr",
                    tls: {
                        enabled: true,
                        server_name: \"$sni\",
                        insecure: true,
                        alpn: ["h3"]
                    }
                }')

            sb_outbounds=$(jq -cn --argjson current "$sb_outbounds" --argjson item "$sb_tuic_json" '$current + [$item]')
            sb_tags=$(jq -cn --argjson current "$sb_tags" --arg tag "$node_name" '$current + [$tag]')
        fi
    fi
    
    # 修复 Bug 3：正确输出文本流
  printf "%s" "$url_all" > "$web_dir/$sub_uuid/url.txt"
    printf "%s" "$url_all" | base64 -w 0 2>/dev/null > "$web_dir/$sub_uuid/sub_b64.txt" || printf "%s" "$url_all" | base64 | tr -d '\r\n' > "$web_dir/$sub_uuid/sub_b64.txt"

    local sub_url="http://$(get_sub_ip):${sub_port}/${sub_uuid}"
    [[ "$(get_sub_ip)" == *":"* ]] && sub_url="http://[$(get_sub_ip)]:${sub_port}/${sub_uuid}"
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


    local singbox_json_tmp=""

    singbox_json_tmp=$(
      mktemp \
        "$web_dir/$sub_uuid/.sing-box.json.XXXXXX"
    ) || {
      red " [错误] 无法创建客户端 JSON 临时文件。"
      return 1
    }

    if ! jq -n \
      --argjson tags "$sb_tags" \
      --argjson nodes "$sb_outbounds" \
      '
        {
          outbounds: (
            [
              {
                type: "selector",
                tag: "Proxy",
                outbounds: (
                  ["Auto"] + $tags
                )
              },
              {
                type: "urltest",
                tag: "Auto",
                outbounds: $tags
              }
            ]
            + $nodes
            + [
              {
                type: "direct",
                tag: "direct"
              },
              {
                type: "block",
                tag: "block"
              },
              {
                type: "dns",
                tag: "dns-out"
              }
            ]
          )
        }
      ' > "$singbox_json_tmp"
    then
      rm -f -- "$singbox_json_tmp"
      red " [错误] 无法生成最终 Sing-box 客户端配置。"
      return 1
    fi

    if ! jq -e '
      (.outbounds | type == "array")
      and (.outbounds | length >= 6)
      and (
        [.outbounds[].tag]
        | all(type == "string" and length > 0)
      )
    ' "$singbox_json_tmp" >/dev/null
    then
      rm -f -- "$singbox_json_tmp"
      red " [错误] 生成的 Sing-box 客户端 JSON 校验失败。"
      return 1
    fi

    chmod 640 "$singbox_json_tmp" || {
      rm -f -- "$singbox_json_tmp"
      return 1
    }

    if ! mv -f -- \
      "$singbox_json_tmp" \
      "$web_dir/$sub_uuid/sing-box.json"
    then
      rm -f -- "$singbox_json_tmp"
      red " [错误] 无法发布 Sing-box 客户端 JSON。"
      return 1
    fi

    chown -R www-data:www-data "$web_dir" 2>/dev/null || chown -R nginx:nginx "$web_dir" 2>/dev/null
    chmod -R 750 "$web_dir"

    local nginx_conf_file="/etc/nginx/conf.d/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf"
    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
        nginx_conf_file="/etc/nginx/sites-available/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf"
    elif [[ $SYSTEM == "Alpine" ]]; then
        mkdir -p /etc/nginx/http.d
        nginx_conf_file="/etc/nginx/http.d/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf"
    else
        mkdir -p /etc/nginx/conf.d
    fi
    
    local listen_ipv6=""
    [[ -f /proc/net/if_inet6 ]] && listen_ipv6="listen [::]:$sub_port;"

    local nginx_conf_candidate=""
    local nginx_conf_backup=""
    local nginx_conf_had_file=0
    local nginx_was_active=0
    local nginx_service_ok=1

    install -d -m 700 /etc/sing-box || return 1

    nginx_conf_candidate=$(
      mktemp /etc/sing-box/nginx-sub.candidate.XXXXXX
    ) || return 1

    if [[ -f "$nginx_conf_file" ]]; then
      nginx_conf_backup=$(
        mktemp /etc/sing-box/nginx-sub.backup.XXXXXX
      ) || {
        rm -f "$nginx_conf_candidate"
        return 1
      }

      if ! cp -L "$nginx_conf_file" "$nginx_conf_backup"; then
        rm -f "$nginx_conf_candidate" "$nginx_conf_backup"
        return 1
      fi

      chmod 600 "$nginx_conf_backup"
      nginx_conf_had_file=1
    fi

    cat << EOF > "$nginx_conf_candidate"
server {
    listen $sub_port;
    server_tokens off;
    access_log off;
    error_log /dev/null crit;
    $listen_ipv6
    
    root $web_dir;

    location = /$sub_uuid {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
        if (\$http_user_agent ~* "(clash|meta|verge|stash|mihomo)") { rewrite ^ /$sub_uuid/clash-meta-sub.yaml last; }
        if (\$http_user_agent ~* "(sing-box|sfa|sfi|sfm)") { rewrite ^ /$sub_uuid/sing-box.json last; }
        rewrite ^ /$sub_uuid/sub_b64.txt last;
    }

    location ~ ^/$sub_uuid/(clash-meta-sub\.yaml|sing-box\.json|sub_b64\.txt|sub_qr\.txt)$ {
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
    }

    location = /$sub_uuid/sub_qr.png {
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0';
    }

    location / { return 444; }
}
EOF

    if ! install -m 0644 "$nginx_conf_candidate" "$nginx_conf_file"; then
      rm -f "$nginx_conf_candidate" "$nginx_conf_backup"
      red " [错误] 无法安装新的 Nginx 配置。"
      return 1
    fi

    rm -f "$nginx_conf_candidate"

    if [[ $SYSTEM == "Ubuntu" || $SYSTEM == "Debian" ]]; then
        ln -sf /etc/nginx/sites-available/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf /etc/nginx/sites-enabled/
    fi

    yellow " 正在执行 Nginx 配置校验，完整输出如下："

    if is_svc_active nginx; then
      nginx_was_active=1
    fi

    if ! nginx -t; then
      nginx_service_ok=0
    else
      if ! svc_enable nginx; then
        nginx_service_ok=0
      elif [[ "$nginx_was_active" -eq 1 ]]; then
        if ! svc_restart nginx; then
          nginx_service_ok=0
        fi
      elif ! svc_start nginx; then
        nginx_service_ok=0
      fi
    fi

    if [[ "$nginx_service_ok" -ne 1 ]]; then
      red " [错误] Nginx 配置校验或服务重载失败，正在恢复旧配置。"

      if [[ "$nginx_conf_had_file" -eq 1 && -f "$nginx_conf_backup" ]]; then
        install -m 0644 "$nginx_conf_backup" "$nginx_conf_file" || true
      else
        rm -f "$nginx_conf_file"

        if [[ "$SYSTEM" == "Ubuntu" || "$SYSTEM" == "Debian" ]]; then
          rm -f /etc/nginx/sites-enabled/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf
        fi
      fi

      rm -f "$nginx_conf_candidate" "$nginx_conf_backup"

      if nginx -t >/dev/null 2>&1; then
        if [[ "$nginx_was_active" -eq 1 ]]; then
          svc_restart nginx >/dev/null 2>&1 || true
        fi
      fi

      return 1
    fi

    rm -f "$nginx_conf_backup"
    green " [✔] Nginx 配置已安全应用。"
}

clean_env() {
    local mode="$1"
    if command -v disable_hy2_port_hopping >/dev/null 2>&1; then
        disable_hy2_port_hopping "quiet" || true
    fi
    close_port_by_tag "hy2-in"
    close_port_by_tag "vless-in"
    close_port_by_tag "tuic-in"
    close_port_by_tag "sub"

    svc_stop sing-box${HY2_INSTANCE_SUFFIX}
    svc_disable sing-box${HY2_INSTANCE_SUFFIX}
    
    rm -f /etc/nginx/conf.d/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf /etc/nginx/sites-available/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf /etc/nginx/sites-enabled/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf /etc/nginx/http.d/sing-box-sub${HY2_INSTANCE_SUFFIX}.conf
    if is_svc_active nginx; then
        if [[ $SYSTEM == "Alpine" ]]; then rc-service nginx reload; else systemctl reload nginx; fi
    fi

    if [[ $SYSTEM == "Alpine" ]]; then
        rm -f /etc/init.d/sing-box${HY2_INSTANCE_SUFFIX}
    else
        rm -f /etc/systemd/system/sing-box${HY2_INSTANCE_SUFFIX}.service
        _smart_run "正在重载系统级守护进程配置" systemctl daemon-reload
    fi
    save_iptables

    rm -rf /etc/sing-box /var/www/sing-box${HY2_INSTANCE_SUFFIX}
    if [[ "$mode" == "all" ]]; then
        rm -f /usr/local/bin/sing-box
        rm -f /usr/bin/666 /usr/bin/hy2
    fi
}

