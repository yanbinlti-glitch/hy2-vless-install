#!/usr/bin/env bash
# shellcheck shell=bash


# 物理地基校验：确保极限环境下目录结构绝对存在
ensure_foundation() {
    if [[ ! -d "/opt/hy2_tmp" ]]; then
        mkdir -p "/opt/hy2_tmp" >/dev/null 2>&1
        chmod 700 "/opt/hy2_tmp" >/dev/null 2>&1
    fi
    # 彻底清理可能导致解压失败的旧版僵尸文件
    rm -rf /opt/hy2_tmp/sing-box* 2>/dev/null
}

ensure_foundation

readonly HY2_CONFIG_TMP_DIR="/etc/sing-box/.tmp"

_prepare_config_tmp_dir() {
  # 防止目录本身被替换为符号链接。
  if [[ -L /etc/sing-box ]]; then
    printf '%s\n' \
      "[错误] /etc/sing-box 不能是符号链接。" \
      >&2
    return 1
  fi

  install -d -m 700 /etc/sing-box ||
    return 1

  if [[ -L "$HY2_CONFIG_TMP_DIR" ]]; then
    printf '%s\n' \
      "[错误] 配置临时目录不能是符号链接：$HY2_CONFIG_TMP_DIR" \
      >&2
    return 1
  fi

  install -d -m 700 "$HY2_CONFIG_TMP_DIR" ||
    return 1

  # 只清理本项目私有目录中的过期临时 JSON。
  find "$HY2_CONFIG_TMP_DIR" \
    -xdev \
    -maxdepth 1 \
    -type f \
    -name 'sb_*.json' \
    -mtime +1 \
    -delete \
    2>/dev/null || true
}

_prepare_config_tmp_dir || {
  return 1 2>/dev/null || exit 1
}

#  5. 安装交互核心流程
# =================================================================
inst_cert() {
    yellow "  系统已统一采用安全自签模式，开始生成伪装 ECC 密钥对..."
    mkdir -p /etc/sing-box
    cert_path="/etc/sing-box/cert.crt"
    key_path="/etc/sing-box/private.key"
    
    echo ""
    yellow "  请选择您的安全伪装域名 (SNI):"
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} www.bing.com (推荐, 默认)"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} www.apple.com"
    echo -e "    ${LIGHT_GREEN}[3]${PLAIN} www.microsoft.com"
    echo -e "    ${LIGHT_GREEN}[4]${PLAIN} 自定义输入"
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [1-4] (默认1): ${PLAIN}"
    read sni_choice || sni_choice=1
    [[ -z "$sni_choice" ]] && sni_choice=1
    
    local cert_sni="www.bing.com"
    case $sni_choice in
        2) cert_sni="www.apple.com" ;;
        3) cert_sni="www.microsoft.com" ;;
        4)
            echo -en " ${LIGHT_YELLOW} ▶ 请输入自定义伪装域名 (如 github.com): ${PLAIN}"
            read cert_sni || cert_sni="www.bing.com"
            [[ -z "$cert_sni" ]] && cert_sni="www.bing.com"
            ;;
    esac
    
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 36500 -key "$key_path" -out "$cert_path" -subj "/CN=$cert_sni"
    
    chmod 644 "$cert_path"
    chmod 600 "$key_path"
    echo "$cert_sni" > /etc/sing-box/cert_sni.txt
    green "  自签证书 ($cert_sni) 生成并降权授权成功！"
}


is_valid_port() {
  local port="$1"
  local min="${2:-1}"
  local max="${3:-65535}"

  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= min && port <= max ))
}

is_port_in_use() {
  local port="$1"
  local proto="${2:-tcp}"

  if [[ "$proto" == "udp" ]]; then
    ss -H -unl 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/ || $i ~ /\]:[0-9]+$/) print $i}' \
      | sed 's/.*://' \
      | grep -qx "$port"
  else
    ss -H -tnl 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/ || $i ~ /\]:[0-9]+$/) print $i}' \
      | sed 's/.*://' \
      | grep -qx "$port"
  fi
}

read_free_port() {
  local prompt="$1"
  local default_value="$2"
  local min="$3"
  local max="$4"
  local proto="$5"
  local label="${6:-端口}"
  local port=""
  local try_count=0

  READ_PORT_RESULT=""

  while true; do
    echo -en "$prompt"
    read -r port || return 1

    if [[ -z "$port" ]]; then
      if [[ "$default_value" == "random" ]]; then
        try_count=0
        while (( try_count < 50 )); do
          port="$(shuf -i "${min}-${max}" -n 1)"
          if ! is_port_in_use "$port" "$proto"; then
            break
          fi
          try_count=$((try_count + 1))
        done
      else
        port="$default_value"
      fi
    fi

    if ! is_valid_port "$port" "$min" "$max"; then
      red " [警告] ${label}无效，必须是 ${min}-${max} 的数字。"
      continue
    fi

    if is_port_in_use "$port" "$proto"; then
      red " [警告] ${proto^^} 端口 $port 已被占用，请重新输入。"
      continue
    fi

    READ_PORT_RESULT="$port"
    return 0
  done
}

inst_sub_port(){
    echo ""
    local history_port=""
    [[ -f /etc/sing-box/sub_port.txt ]] && history_port=$(cat /etc/sing-box/sub_port.txt)
    
    if [[ -n "$history_port" ]]; then
        echo -en " ${LIGHT_YELLOW} ▶ 检测到历史订阅端口 [${history_port}]，是否沿用以保持订阅链接不变？(y/n) [默认: y]: ${PLAIN}"
        read use_hist || use_hist="y"
        [[ -z "$use_hist" ]] && use_hist="y"
        if [[ "$use_hist" == "y" || "$use_hist" == "Y" ]]; then
            sub_port_input=$history_port
            green " 沿用历史订阅 HTTP 端口: $sub_port_input"
            open_port "$sub_port_input" "tcp" "sub"
            return
        fi
    fi

    echo -en " ${LIGHT_YELLOW} ▶ 设置 Nginx 聚合订阅服务端口 [1024-65535] (回车随机): ${PLAIN}"
    read sub_port_input || exit 1
    [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    
    while [[ ! "$sub_port_input" =~ ^[0-9]+$ ]] || [[ "$sub_port_input" -lt 1024 ]] || [[ "$sub_port_input" -gt 65535 ]]; do
        red " [警告] 端口无效！重新设置: "
        read sub_port_input || exit 1
        [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    done
    
    while ss -tnl | grep -E -q "(:|^)$sub_port_input( |$)"; do
        red " [警告] 端口 $sub_port_input 已被占用！重新设置: "
        read sub_port_input || exit 1
        [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-30000 -n 1)
    done
    green " 订阅 HTTP 端口已设置为: $sub_port_input"
    open_port $sub_port_input "tcp" "sub"
    echo "$sub_port_input" > /etc/sing-box/sub_port.txt
}

_ensure_singbox_service_account() {
  local login_shell="/usr/sbin/nologin"
  local uid=""

  if [[ ! -x "$login_shell" ]]; then
    if [[ -x /sbin/nologin ]]; then
      login_shell="/sbin/nologin"
    else
      login_shell="/bin/false"
    fi
  fi

  if ! grep -q '^sing-box:' /etc/group 2>/dev/null; then
    if [[ "$SYSTEM" == "Alpine" ]]; then
      addgroup -S sing-box || return 1
    else
      groupadd --system sing-box || return 1
    fi
  fi

  if id -u sing-box >/dev/null 2>&1; then
    uid="$(id -u sing-box)"

    if [[ "$uid" == "0" ]]; then
      red " [错误] sing-box 账户不能映射到 root。"
      return 1
    fi
  else
    if [[ "$SYSTEM" == "Alpine" ]]; then
      adduser \
        -S \
        -D \
        -H \
        -h /var/lib/sing-box \
        -s "$login_shell" \
        -G sing-box \
        sing-box || return 1
    else
      useradd \
        --system \
        --gid sing-box \
        --home-dir /var/lib/sing-box \
        --shell "$login_shell" \
        sing-box || return 1
    fi
  fi
}

_secure_singbox_runtime_permissions() {
  local item=""

  _ensure_singbox_service_account || {
    red " [错误] 无法创建或验证 Sing-box 专用账户。"
    return 1
  }

  if [[ -L /etc/sing-box ]]; then
    red " [错误] /etc/sing-box 不能是符号链接。"
    return 1
  fi

  install \
    -d \
    -o root \
    -g sing-box \
    -m 0750 \
    /etc/sing-box || return 1

  install \
    -d \
    -o sing-box \
    -g sing-box \
    -m 0750 \
    /var/lib/sing-box || return 1

  for item in \
    /etc/sing-box/config.json \
    /etc/sing-box/config.json.last-known-good \
    /etc/sing-box/cert.crt \
    /etc/sing-box/private.key
  do
    [[ -e "$item" ]] || continue

    if [[ -L "$item" || ! -f "$item" ]]; then
      red " [错误] Sing-box 敏感文件必须是普通文件：$item"
      return 1
    fi

    chown root:sing-box "$item" || return 1
    chmod 0640 "$item" || return 1
  done
}

setup_singbox_service() {
    local total_mem_mb=$(free -m | awk '/Mem:/ {print $2}')
    local sys_gomem="50MiB"
    local sys_gogc="20"
    if [[ -n "$total_mem_mb" && "$total_mem_mb" -gt 1024 ]]; then
        sys_gomem="250MiB"
        sys_gogc="60"
    elif [[ -n "$total_mem_mb" && "$total_mem_mb" -gt 400 ]]; then
        sys_gomem="100MiB"
        sys_gogc="40"
    fi
    yellow "  根据物理机内存 ($total_mem_mb MB) 动态下发 Go 回收策略: GOMEMLIMIT=$sys_gomem"

    yellow "  正在装配 Sing-box 系统级守护进程 (挂载高强度沙盒防御)..."
    _secure_singbox_runtime_permissions || return 1

  if [[ $SYSTEM == "Alpine" ]]; then
        cat << 'EOF' > /etc/init.d/sing-box
#!/sbin/openrc-run
export GOMEMLIMIT=50MiB
export GOGC=20
description="Sing-box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_user="sing-box:sing-box"
capabilities="^cap_net_bind_service"
command_background=true
pidfile="/run/sing-box.pid"
respawn="yes"
respawn_max=5
respawn_period=60
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"
rc_ulimit="-n 524288"

start_pre() {
  checkpath     --file     --mode 0640     --owner sing-box:sing-box     /var/log/sing-box.log
}
EOF
        chmod +x /etc/init.d/sing-box
    else
        cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
Environment="GOMEMLIMIT=50MiB"
Environment="GOGC=20"
Type=simple
User=sing-box
Group=sing-box
WorkingDirectory=/var/lib/sing-box
LimitNOFILE=524288
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogLevel=warning
UMask=0027
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
ReadOnlyPaths=/etc/sing-box
ReadWritePaths=/var/lib/sing-box

[Install]
WantedBy=multi-user.target
EOF

        # 商业级安全与日志轮转配置
        mkdir -p /etc/logrotate.d
        cat << 'LOGEOF' > /etc/logrotate.d/sing-box
/var/log/sing-box.log {
    daily
    rotate 3
    missingok
    notifempty
    compress
    copytruncate
}
LOGEOF
        _secure_singbox_runtime_permissions || return 1
        _smart_run "正在重载系统级守护进程配置" systemctl daemon-reload
    fi

    # 注入后台幽灵清道夫 (每天凌晨 4 点智能清理极限小鸡缓存)
    cat << 'CLEANEOF' > /usr/local/bin/hy2_auto_clean.sh
#!/bin/sh
set -eu

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 只清理本项目拥有的临时目录。
if [ -d /opt/hy2_tmp ]; then
  find /opt/hy2_tmp \
    -xdev \
    -type f \
    -mtime +1 \
    -delete \
    2>/dev/null || true

  find /opt/hy2_tmp \
    -xdev \
    -mindepth 1 \
    -type d \
    -empty \
    -mtime +1 \
    -delete \
    2>/dev/null || true
fi
CLEANEOF
    chmod +x /usr/local/bin/hy2_auto_clean.sh
    if ! crontab -l 2>/dev/null | grep -q "hy2_auto_clean.sh"; then
        (crontab -l 2>/dev/null || true; echo "0 4 * * * /usr/local/bin/hy2_auto_clean.sh >/dev/null 2>&1") | crontab -
    fi

    if [[ -f /etc/init.d/sing-box ]]; then
        sed -i "s/GOMEMLIMIT=50MiB/GOMEMLIMIT=$sys_gomem/g" /etc/init.d/sing-box
        sed -i "s/GOGC=20/GOGC=$sys_gogc/g" /etc/init.d/sing-box
    fi
    if [[ -f /etc/systemd/system/sing-box.service ]]; then
        sed -i "s/GOMEMLIMIT=50MiB/GOMEMLIMIT=$sys_gomem/g" /etc/systemd/system/sing-box.service
        sed -i "s/GOGC=20/GOGC=$sys_gogc/g" /etc/systemd/system/sing-box.service
        _smart_run "正在重载系统级守护进程配置" systemctl daemon-reload 2
    fi
}

build_base_json() {
    cat << EOF > /etc/sing-box/config.json
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "google",
        "server": "8.8.8.8",
        "server_port": 53
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [
      {
        "ip_cidr": [ "169.254.0.0/16", "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7", "fe80::/10" ],
        "action": "route",
        "outbound": "block"
      }
    ]
  }
}
EOF
}


migrate_legacy_dns_config() {
    # 兼容 sing-box 1.12+：自动把旧版 dns.servers[].address 迁移为新版 server/type 写法
    # 注意：DNS 服务器不要写 detour: direct。新版 sing-box 会报：detour to an empty direct outbound makes no sense。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.dns.servers[]? | select((has("address")) and ((has("type") | not) or (.type == null)))' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到旧版 DNS 配置，正在自动迁移为 sing-box 1.12+ 新格式..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.dns.$(date +%F-%H%M%S)" || true

        jq '
          .dns.servers |= map(
            if (has("address") and ((has("type") | not) or (.type == null))) then
              . as $old |
              {
                "type": "udp",
                "tag": ($old.tag // "google"),
                "server": $old.address,
                "server_port": ($old.server_port // 53)
              }
            else
              .
            end
          )
        ' /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_dns.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_dns.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_dns.$$.json" /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] DNS 配置迁移完成。"
    fi
}

fix_dns_detour_direct_config() {
    # 修复已经被迁移成新 DNS 但仍残留 detour: direct 的配置。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.dns.servers[]? | select((.detour // "") == "direct")' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到 DNS 残留 detour=direct，正在移除以兼容新版 sing-box..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.dns-detour.$(date +%F-%H%M%S)" || true
        jq '(.dns.servers[]? | select((.detour // "") == "direct")) |= del(.detour)'           /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_dns_detour.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_dns_detour.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_dns_detour.$$.json" /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] DNS detour 兼容修复完成。"
    fi
}

migrate_legacy_route_config() {
    # sing-box 1.11+ 推荐 Route Action；旧配置只有 outbound 时补 action=route。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    if jq -e '.route.rules[]? | select((has("outbound")) and ((has("action") | not) or (.action == null)))' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  检测到旧版路由规则，正在补充 action=route..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.route.$(date +%F-%H%M%S)" || true
        jq '(.route.rules[]? | select((has("outbound")) and ((has("action") | not) or (.action == null))) | .action) = "route"'           /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_route.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_route.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_route.$$.json" /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] 路由规则兼容修复完成。"
    fi
}

fix_listen_for_no_ipv6() {
    # 某些精简 Alpine/LXC 没有 IPv6，listen="::" 会导致服务无法监听。
    [[ -f /etc/sing-box/config.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    [[ -f /proc/net/if_inet6 ]] && return 0

    if jq -e '.inbounds[]? | select(.listen == "::")' /etc/sing-box/config.json >/dev/null 2>&1; then
        yellow "  当前系统未启用 IPv6，正在把监听地址从 :: 改为 0.0.0.0..."
        cp -a /etc/sing-box/config.json "/etc/sing-box/config.json.bak.listen.$(date +%F-%H%M%S)" || true
        jq '(.inbounds[]? | select(.listen == "::") | .listen) = "0.0.0.0"'           /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_listen.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_listen.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_listen.$$.json" /etc/sing-box/config.json
        chmod 600 /etc/sing-box/config.json
        green "  [✔] 监听地址兼容修复完成。"
    fi
}

ensure_singbox_core() (
  local install_path="/usr/local/bin/sing-box"
  local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local arch=""
  local sb_arch=""
  local sb_version=""
  local sb_asset=""
  local official_url=""
  local api_asset_url=""
  local expected_digest=""
  local expected_hash=""
  local actual_hash=""
  local work_dir=""
  local release_json=""
  local archive=""
  local archive_list=""
  local extract_root=""
  local extract_dir=""
  local candidate=""
  local install_tmp=""
  local previous_binary=""

  # 已有核心必须能实际执行，不能只检查可执行位。
  if [[ -x "$install_path" ]] &&
     "$install_path" version >/dev/null 2>&1
  then
    return 0
  fi

  if [[ -L "$install_path" ]]; then
    red " [致命错误] $install_path 不能是符号链接。"
    return 1
  fi

  local required_command

  for required_command in \
    curl \
    jq \
    sha256sum \
    tar \
    awk \
    install \
    mktemp
  do
    if ! command -v "$required_command" \
      >/dev/null 2>&1
    then
      red " [致命错误] 缺少必要命令：$required_command"
      return 1
    fi
  done

  if [[ -L /opt/hy2_tmp ]]; then
    red " [致命错误] /opt/hy2_tmp 不能是符号链接。"
    return 1
  fi

  install -d -m 700 /opt/hy2_tmp || {
    red " [致命错误] 无法创建安全下载目录。"
    return 1
  }

  chmod 700 /opt/hy2_tmp || return 1

  work_dir=$(
    mktemp -d /opt/hy2_tmp/sing-box-install.XXXXXX
  ) || {
    red " [致命错误] 无法创建 Sing-box 私有工作目录。"
    return 1
  }

  trap '
    rm -rf -- "$work_dir"

    if [[ -n "${install_tmp:-}" ]]; then
      rm -f -- "$install_tmp"
    fi
  ' EXIT

  release_json="$work_dir/release.json"
  archive="$work_dir/sing-box.tar.gz"
  archive_list="$work_dir/archive.list"
  extract_root="$work_dir/extracted"

  yellow " 正在从 Sing-box 官方 GitHub API 获取最新稳定版本……"

  if ! curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 2 \
    --retry-delay 1 \
    "$api_url" \
    --output "$release_json"
  then
    red " [致命错误] 无法获取 Sing-box 官方发布信息。"
    return 1
  fi

  if ! jq -e \
    '.tag_name and (.assets | type == "array")' \
    "$release_json" \
    >/dev/null
  then
    red " [致命错误] Sing-box 官方发布信息格式无效。"
    return 1
  fi

  sb_version=$(
    jq -r '.tag_name // empty' "$release_json"
  )

  if [[ ! "$sb_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    red " [致命错误] Sing-box 版本号格式异常：$sb_version"
    return 1
  fi

  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64)
      sb_arch="amd64"
      ;;

    aarch64|arm64)
      sb_arch="arm64"
      ;;

    armv7*|armv6*)
      sb_arch="armv7"
      ;;

    i386|i686)
      sb_arch="386"
      ;;

    s390x)
      sb_arch="s390x"
      ;;

    *)
      red " [致命错误] Sing-box 暂不支持该 CPU 架构：$arch"
      return 1
      ;;
  esac

  sb_asset="sing-box-${sb_version#v}-linux-${sb_arch}.tar.gz"

  official_url="$(
    printf '%s' \
      "https://github.com/SagerNet/sing-box/releases/download/" \
      "${sb_version}/" \
      "${sb_asset}"
  )"

  api_asset_url=$(
    jq -r \
      --arg name "$sb_asset" \
      '
        .assets[]
        | select(.name == $name)
        | .browser_download_url // empty
      ' \
      "$release_json" |
      head -n1
  )

  expected_digest=$(
    jq -r \
      --arg name "$sb_asset" \
      '
        .assets[]
        | select(.name == $name)
        | .digest // empty
      ' \
      "$release_json" |
      head -n1
  )

  if [[ "$api_asset_url" != "$official_url" ]]; then
    red " [致命错误] 官方 API 返回了非预期下载地址。"
    red " 预期：$official_url"
    red " 实际：$api_asset_url"
    return 1
  fi

  if [[ ! "$expected_digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]]
  then
    red " [致命错误] 官方发布资产缺少有效 SHA-256 digest。"
    red " [安全策略] 未校验的 Sing-box 核心不会被安装。"
    return 1
  fi

  expected_hash="${expected_digest#sha256:}"
  expected_hash="${expected_hash,,}"

  yellow " 目标版本：$sb_version ($sb_arch)"
  yellow " 正在从 Sing-box 官方 GitHub Release 下载……"

  if ! curl \
    --fail \
    --show-error \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --connect-timeout 15 \
    --max-time 180 \
    --retry 3 \
    --retry-delay 2 \
    "$official_url" \
    --output "$archive"
  then
    red " [致命错误] Sing-box 官方核心下载失败。"
    return 1
  fi

  if [[ ! -s "$archive" ]]; then
    red " [致命错误] 下载到的 Sing-box 压缩包为空。"
    return 1
  fi

  actual_hash=$(
    sha256sum "$archive" |
      awk '{print tolower($1)}'
  )

  if [[ "$actual_hash" != "$expected_hash" ]]; then
    red " [致命错误] Sing-box SHA-256 校验失败。"
    red " 期望：$expected_hash"
    red " 实际：$actual_hash"
    return 1
  fi

  green " [✔] Sing-box 官方 SHA-256 校验通过。"

  if ! tar -tzf "$archive" > "$archive_list"; then
    red " [致命错误] 无法读取 Sing-box 压缩包目录。"
    return 1
  fi

  # 拒绝绝对路径、父目录穿越和空文件名。
  if awk '
    BEGIN {
      bad = 0
    }

    /^$/ {
      bad = 1
    }

    /^\// {
      bad = 1
    }

    /(^|\/)\.\.(\/|$)/ {
      bad = 1
    }

    END {
      exit bad ? 0 : 1
    }
  ' "$archive_list"
  then
    red " [致命错误] Sing-box 压缩包包含不安全路径。"
    return 1
  fi

  # 拒绝符号链接和硬链接，避免解压时越界写入。
  if tar -tvzf "$archive" |
    awk '
      $1 ~ /^[lh]/ {
        found = 1
      }

      END {
        exit found ? 0 : 1
      }
    '
  then
    red " [致命错误] Sing-box 压缩包包含链接条目。"
    return 1
  fi

  mkdir -p "$extract_root" || return 1
  chmod 700 "$extract_root" || return 1

  if ! tar -xzf "$archive" -C "$extract_root"; then
    red " [致命错误] Sing-box 核心解压失败。"
    return 1
  fi

  extract_dir="$extract_root/sing-box-${sb_version#v}-linux-${sb_arch}"
  candidate="$extract_dir/sing-box"

  if [[ ! -f "$candidate" ||
        -L "$candidate" ]]
  then
    red " [致命错误] 压缩包中未找到安全的 Sing-box 二进制。"
    return 1
  fi

  chmod 755 "$candidate" || return 1

  if ! "$candidate" version >/dev/null 2>&1; then
    red " [致命错误] 解压后的 Sing-box 二进制自检失败。"
    return 1
  fi

  install_tmp=$(
    mktemp /usr/local/bin/.sing-box.new.XXXXXX
  ) || {
    red " [致命错误] 无法创建二进制原子安装文件。"
    return 1
  }

  if ! install -m 0755 "$candidate" "$install_tmp"; then
    red " [致命错误] 无法准备新的 Sing-box 二进制。"
    return 1
  fi

  if ! "$install_tmp" version >/dev/null 2>&1; then
    red " [致命错误] 待安装的 Sing-box 二进制自检失败。"
    return 1
  fi

  if [[ -e "$install_path" ]]; then
    previous_binary="$work_dir/sing-box.previous"

    if ! cp -a -- "$install_path" "$previous_binary"; then
      red " [致命错误] 无法备份现有 Sing-box 二进制。"
      return 1
    fi
  fi

  if ! mv -f -- "$install_tmp" "$install_path"; then
    red " [致命错误] 无法原子替换 Sing-box 二进制。"
    return 1
  fi

  install_tmp=""

  if ! "$install_path" version >/dev/null 2>&1; then
    red " [致命错误] 新 Sing-box 安装后自检失败，正在回滚。"

    rm -f -- "$install_path"

    if [[ -f "$previous_binary" ]]; then
      cp -a -- "$previous_binary" "$install_path" || true
    fi

    return 1
  fi

  green " [✔] Sing-box ($sb_version | $sb_arch) 已安全安装。"
  return 0
)

normalize_singbox_config() {
    migrate_legacy_dns_config
    fix_dns_detour_direct_config
    migrate_legacy_route_config
    fix_listen_for_no_ipv6
}

check_singbox_config() {
    ensure_singbox_core || return 1
    normalize_singbox_config
    if [[ -x /usr/local/bin/sing-box && -f /etc/sing-box/config.json ]]; then
        yellow "  正在执行 sing-box 配置校验，完整输出如下："
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json 2>&1 | tee /opt/hy2_tmp/sing-box-check.log
        local rc=${PIPESTATUS[0]}
        if [[ $rc -ne 0 ]]; then
            red "  [致命错误] Sing-box 配置校验失败，服务未重启。"
            return $rc
        fi
        green "  [✔] Sing-box 配置校验通过。"
    else
        red "  [致命错误] 未找到 /usr/local/bin/sing-box 或 /etc/sing-box/config.json。"
        return 1
    fi
    return 0
}

SINGBOX_CONFIG_TX_BACKUP=""
SINGBOX_CONFIG_TX_HAD_FILE=0
SINGBOX_CONFIG_TX_SERVICE_WAS_ACTIVE=0

_reset_singbox_config_transaction() {
  SINGBOX_CONFIG_TX_BACKUP=""
  SINGBOX_CONFIG_TX_HAD_FILE=0
  SINGBOX_CONFIG_TX_SERVICE_WAS_ACTIVE=0
}

_begin_singbox_config_transaction() {
  local backup=""

  if [[ -n "$SINGBOX_CONFIG_TX_BACKUP" ]]; then
    rm -f -- "$SINGBOX_CONFIG_TX_BACKUP"
  fi

  _reset_singbox_config_transaction

  if [[ -L /etc/sing-box ]]; then
    red " [错误] /etc/sing-box 不能是符号链接。"
    return 1
  fi

  install -d -m 700 /etc/sing-box ||
    return 1

  if is_svc_active sing-box; then
    SINGBOX_CONFIG_TX_SERVICE_WAS_ACTIVE=1
  fi

  if [[ -e /etc/sing-box/config.json ]]; then
    if [[ -L /etc/sing-box/config.json ||
          ! -f /etc/sing-box/config.json ]]
    then
      red " [错误] config.json 必须是普通文件。"
      return 1
    fi

    backup=$(
      mktemp \
        /etc/sing-box/.config.rollback.XXXXXX
    ) || return 1

    if ! cp -a -- \
      /etc/sing-box/config.json \
      "$backup"
    then
      rm -f -- "$backup"
      return 1
    fi

    chmod 600 "$backup" || {
      rm -f -- "$backup"
      return 1
    }

    SINGBOX_CONFIG_TX_BACKUP="$backup"
    SINGBOX_CONFIG_TX_HAD_FILE=1
  fi

  return 0
}

_restore_singbox_config_transaction() {
  local restore_rc=0

  if [[ "$SINGBOX_CONFIG_TX_HAD_FILE" -eq 1 ]]; then
    if [[ -z "$SINGBOX_CONFIG_TX_BACKUP" ||
          ! -f "$SINGBOX_CONFIG_TX_BACKUP" ]]
    then
      red " [错误] 配置回滚文件不存在。"
      return 1
    fi

    if ! install -m 600 \
      "$SINGBOX_CONFIG_TX_BACKUP" \
      /etc/sing-box/config.json
    then
      restore_rc=1
    fi
  else
    rm -f -- /etc/sing-box/config.json
  fi

  if [[ -n "$SINGBOX_CONFIG_TX_BACKUP" ]]; then
    rm -f -- "$SINGBOX_CONFIG_TX_BACKUP"
  fi

  _reset_singbox_config_transaction

  return "$restore_rc"
}

_commit_singbox_config_transaction() {
  local candidate=""

  if [[ -f /etc/sing-box/config.json ]]; then
    candidate=$(
      mktemp \
        /etc/sing-box/.config.last-good.XXXXXX
    ) || return 1

    if ! cp -a -- \
      /etc/sing-box/config.json \
      "$candidate"
    then
      rm -f -- "$candidate"
      return 1
    fi

    chmod 600 "$candidate" || {
      rm -f -- "$candidate"
      return 1
    }

    if ! mv -f -- \
      "$candidate" \
      /etc/sing-box/config.json.last-known-good
    then
      rm -f -- "$candidate"
      return 1
    fi
  fi

  if [[ -n "$SINGBOX_CONFIG_TX_BACKUP" ]]; then
    rm -f -- "$SINGBOX_CONFIG_TX_BACKUP"
  fi

  _reset_singbox_config_transaction
}

_abort_singbox_config_update() {
  local reason="${1:-配置修改失败}"

  red " [错误] $reason，正在恢复修改前配置。"

  if _restore_singbox_config_transaction; then
    yellow " [回滚] 已恢复修改前的 Sing-box 配置。"
  else
    red " [错误] Sing-box 配置自动恢复失败。"
  fi

  return 1
}

restart_singbox_checked() {
  if ! _secure_singbox_runtime_permissions; then
    red " [错误] 无法应用 Sing-box 安全文件权限。"
    return 1
  fi

  local service_was_active=0
  local restart_ok=1

  service_was_active="$SINGBOX_CONFIG_TX_SERVICE_WAS_ACTIVE"

  if ! check_singbox_config; then
    _abort_singbox_config_update \
      "Sing-box 配置校验失败"

    return 1
  fi

  if [[ "$service_was_active" -eq 1 ]]; then
    if ! svc_restart sing-box; then
      restart_ok=0
    fi
  else
    if ! svc_start sing-box; then
      restart_ok=0
    fi
  fi

  sleep 1

  if [[ "$restart_ok" -ne 1 ]] ||
     ! is_svc_active sing-box
  then
    red " [错误] Sing-box 新配置启动失败。"

    if [[ "$SYSTEM" == "Alpine" ]]; then
      tail -n 80 /var/log/sing-box.log \
        2>/dev/null || true
    else
      journalctl \
        -u sing-box \
        -n 80 \
        --no-pager \
        2>/dev/null || true
    fi

    if ! _restore_singbox_config_transaction; then
      red " [错误] 无法恢复修改前配置。"
      return 1
    fi

    yellow " [回滚] 已恢复修改前配置。"

    if [[ "$service_was_active" -eq 1 ]]; then
      if check_singbox_config >/dev/null 2>&1 &&
         (
           svc_restart sing-box \
             >/dev/null 2>&1 ||
           svc_start sing-box \
             >/dev/null 2>&1
         )
      then
        green " [回滚] 原 Sing-box 服务已恢复运行。"
      else
        red " [错误] 原配置已恢复，但服务重新启动失败。"
      fi
    else
      svc_stop sing-box >/dev/null 2>&1 || true
    fi

    return 1
  fi

  if ! _commit_singbox_config_transaction; then
    red " [错误] 无法保存最后可用配置快照。"
    return 1
  fi

  green " [✔] Sing-box 新配置已生效并保存为最后可用版本。"
  return 0
}

inst_hysteria2() {
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
    yellow "  Hysteria 2 主端口与网络配置"
    read_free_port " ${LIGHT_YELLOW} ▶ 设置 Hysteria 2 主端口 (UDP) [10000-65535] (回车随机): ${PLAIN}" "random" 10000 65535 "udp" "Hysteria 2 主端口" || return 1
port="$READ_PORT_RESULT"
green " 节点主端口已设置为: $port (UDP)"
open_port "$port" "udp" "hy2-in"
echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 设置节点连接密码 (回车自动生成): ${PLAIN}"
    read auth_pwd || exit 1
    [[ -z $auth_pwd ]] && auth_pwd=$(gen_random_str 16)
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 Hy2_Node]: ${PLAIN}"
    read custom_node_name || exit 1
    [[ -z $custom_node_name ]] && custom_node_name="Hy2_Node"
    echo "$custom_node_name" > /etc/sing-box/hy2_name.txt
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 是否开启防阻断 Salamander 混淆？(y/n) [默认: y]: ${PLAIN}"
    read enable_obfs || exit 1
    [[ -z $enable_obfs ]] && enable_obfs="y"
    local obfs_pwd=""
    if [[ "$enable_obfs" == "y" || "$enable_obfs" == "Y" ]]; then
        obfs_pwd=$(gen_random_str 12)
        green " 已开启混淆，密钥为: $obfs_pwd"
    fi
    
    local listen_addr="::"
    [[ ! -f /proc/net/if_inet6 ]] && listen_addr="0.0.0.0"

  if ! _begin_singbox_config_transaction; then
    red " [错误] 无法创建配置事务备份。"
    return 1
  fi

    jq --arg p "$port" --arg pwd "$auth_pwd" --arg cp "/etc/sing-box/cert.crt" --arg kp "/etc/sing-box/private.key" --arg listen "$listen_addr" '
    .inbounds += [{
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": $listen,
      "listen_port": ($p | tonumber),
      "users": [{"password": $pwd}],
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cp, "key_path": $kp }
    }]' /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" /etc/sing-box/config.json || {
    _abort_singbox_config_update "生成新 Sing-box 配置失败"
    return 1
  }
    
    if [[ -n "$obfs_pwd" ]]; then
        jq --arg obfs "$obfs_pwd" '( .inbounds[] | select(.tag=="hy2-in") ) += { "obfs": {"type": "salamander", "password": $obfs} }' /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" /etc/sing-box/config.json || {
    _abort_singbox_config_update "生成新 Sing-box 配置失败"
    return 1
  }
    fi
    
    chmod 600 /etc/sing-box/config.json
    if ! svc_enable sing-box; then
    _abort_singbox_config_update \
      "无法启用 Sing-box 服务"

    return 1
  fi
    restart_singbox_checked || return 1
    generate_client_configs
    
    echo ""
    green "  [✔] Hysteria 2 服务端已追加部署成功！"
    sleep 2
}

inst_vless_reality() {
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
    yellow "  VLESS + Reality 端口与特征配置"
    read_free_port " ${LIGHT_YELLOW} ▶ 请设置 VLESS 主端口 (TCP) [1-65535] (回车默认 443，可自定义): ${PLAIN}" "443" 1 65535 "tcp" "VLESS 主端口" || return 1
port="$READ_PORT_RESULT"
green " 节点主端口已设置为: $port (TCP)"
open_port "$port" "tcp" "vless-in"
echo ""
    local v_sni=$(cat /etc/sing-box/cert_sni.txt 2>/dev/null || echo "www.microsoft.com")
    yellow "  VLESS Reality 伪装域名已自动继承基础设定: $v_sni"
    
    yellow "  正在通过 Sing-box 核心生成原生 x25519 密钥对与 Short ID..."
    local keypair_json=$(/usr/local/bin/sing-box generate reality-keypair)
    local v_private_key=$(echo "$keypair_json" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    local v_public_key=$(echo "$keypair_json" | awk '/PublicKey/ {print $2}' | tr -d '"')
    local v_short_id=$(/usr/local/bin/sing-box generate rand --hex 8 2>/dev/null)
    local v_uuid=$(/usr/local/bin/sing-box generate uuid 2>/dev/null)
    [[ -z "$v_uuid" ]] && v_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "11223344-5566-7788-9900-aabbccddeeff")
    [[ -z "$v_short_id" ]] && v_short_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 16 || echo "1122334455667788")
    
    echo "$v_public_key" > /etc/sing-box/reality_pub.txt
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 Vless_Reality_Node]: ${PLAIN}"
    read custom_node_name || exit 1
    [[ -z $custom_node_name ]] && custom_node_name="Vless_Reality_Node"
    echo "$custom_node_name" > /etc/sing-box/vless_name.txt
    
    local listen_addr="::"
    [[ ! -f /proc/net/if_inet6 ]] && listen_addr="0.0.0.0"

    yellow "  正在写入 VLESS Reality 推荐参数：Vision + Reality + TCP Fast Open + 自适应监听..."
  if ! _begin_singbox_config_transaction; then
    red " [错误] 无法创建配置事务备份。"
    return 1
  fi

    jq --arg p "$port" --arg uuid "$v_uuid" --arg priv "$v_private_key" --arg sid "$v_short_id" --arg sni "$v_sni" --arg listen "$listen_addr" '
    .inbounds += [{
      "type": "vless",
      "tag": "vless-in",
      "listen": $listen,
      "listen_port": ($p | tonumber),
      "tcp_fast_open": true,
      "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": { "server": $sni, "server_port": 443 },
          "private_key": $priv,
          "short_id": [$sid]
        }
      }
    }]' /etc/sing-box/config.json > "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" && [ -s "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" ] && mv -f -- "$HY2_CONFIG_TMP_DIR/sb_config.$$.json" /etc/sing-box/config.json || {
    _abort_singbox_config_update "生成新 Sing-box 配置失败"
    return 1
  }
    
    chmod 600 /etc/sing-box/config.json
    if ! svc_enable sing-box; then
    _abort_singbox_config_update \
      "无法启用 Sing-box 服务"

    return 1
  fi
    restart_singbox_checked || return 1
    generate_client_configs
    
    echo ""
    green "  [✔] VLESS + Reality 服务端已追加部署成功！"
    yellow "  已自动写入 VLESS Reality 推荐配置：Vision + Reality + TCP Fast Open + 自适应监听。"
    yellow "  端口保持您安装时的自定义选择；如需 TCP 系统层加速，可在主菜单 [7] 开启 BBR。"
    sleep 2
}

inst_singbox() {
    check_env
    normalize_singbox_config
    check_installed_nodes
    
    if [[ $has_hy2 -eq 1 && $has_vless -eq 1 ]]; then
        echo ""
        red "  [阻断] 您已成功部署了双节点 (Hysteria 2 + VLESS)，无需重复安装！"
        sleep 2; return
    fi
    
    if [[ $has_hy2 -eq 1 ]]; then
        yellow "  检测到您已安装 Hysteria 2，正在为您直接拉起 VLESS 补充安装流程..."
        sleep 2; inst_vless_reality; return
    elif [[ $has_vless -eq 1 ]]; then
        yellow "  检测到您已安装 VLESS，正在为您直接拉起 Hysteria 2 补充安装流程..."
        sleep 2; inst_hysteria2; return
    fi
    
    clear
    echo ""
    green " ──────────────────────────────────────────────────────────"
    green "                 底层代理协议选择配置                      "
    green " ──────────────────────────────────────────────────────────"
    echo ""
    yellow "  Sing-box 核心支持多协议矩阵，您可以先选装一个，后续可再次进入菜单补齐："
    echo ""
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}Hysteria 2 (基于 UDP/QUIC，极速抗丢包，默认推荐)${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_PURPLE}VLESS + Reality (基于 TCP/XTLS，指纹级伪装，抗封锁推荐)${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [1-2] (默认1): ${PLAIN}"
    read protoInput || protoInput=1
    [[ -z "$protoInput" ]] && protoInput=1

    if [[ "$protoInput" == "2" ]]; then
        inst_vless_reality
    else
        inst_hysteria2
    fi
}

