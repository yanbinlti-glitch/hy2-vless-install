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

FIREWALL_STATE="/etc/sing-box${HY2_INSTANCE_SUFFIX}/.firewall_state"

_validate_firewall_args() {
  local port="${1:-}"
  local proto="${2:-}"
  local tag="${3:-}"

  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 )) || return 1

  [[ "$proto" == "tcp" ||
     "$proto" == "udp" ]] || return 1

  [[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
    return 1
}

_firewall_state_init() {
  install -d -m 750 /etc/sing-box${HY2_INSTANCE_SUFFIX}; chown root:sing-box /etc/sing-box${HY2_INSTANCE_SUFFIX} 2>/dev/null || true
  touch "$FIREWALL_STATE"
  chmod 600 "$FIREWALL_STATE"
}

_firewall_state_add() {
  local line="$1"

  _firewall_state_init || return 1

  grep -qxF "$line" "$FIREWALL_STATE" \
    2>/dev/null ||
    printf '%s\n' "$line" >> "$FIREWALL_STATE"
}

_open_iptables_rule() {
  local tool="$1"
  local family="$2"
  local port="$3"
  local proto="$4"
  local tag="$5"
  local comment
  local state_line

  command -v "$tool" >/dev/null 2>&1 ||
    return 0

  comment="hy2-vless:${tag}:${proto}:${port}"

  state_line="$(
    printf 'v2|%s|iptables|%s|%s|%s|%s' \
      "$tag" \
      "$family" \
      "$proto" \
      "$port" \
      "$comment"
  )"

  # 如果专属规则已经存在，可以安全恢复状态记录。
  if "$tool" \
    -C INPUT \
    -p "$proto" \
    --dport "$port" \
    -m comment \
    --comment "$comment" \
    -j ACCEPT \
    2>/dev/null
  then
    _firewall_state_add "$state_line"
    return 0
  fi

  # 已有普通规则时不接管，也不写入本项目状态。
  if "$tool" \
    -C INPUT \
    -p "$proto" \
    --dport "$port" \
    -j ACCEPT \
    2>/dev/null
  then
    green \
      " [防火墙] ${family} $proto 端口 $port 已由其他规则放行，不接管该规则。"

    return 0
  fi

  "$tool" \
    -I INPUT \
    -p "$proto" \
    --dport "$port" \
    -m comment \
    --comment "$comment" \
    -j ACCEPT

  if ! _firewall_state_add "$state_line"; then
    "$tool" \
      -D INPUT \
      -p "$proto" \
      --dport "$port" \
      -m comment \
      --comment "$comment" \
      -j ACCEPT \
      >/dev/null 2>&1 || true

    return 1
  fi
}

open_port() {
  local port="${1:-}"
  local proto="${2:-}"
  local tag="${3:-}"
  local state_line

  if ! _validate_firewall_args \
    "$port" \
    "$proto" \
    "$tag"
  then
    printf \
      '[错误] 非法防火墙参数: tag=%q proto=%q port=%q\n' \
      "$tag" \
      "$proto" \
      "$port" \
      >&2

    return 1
  fi

  _firewall_state_init || return 1

  yellow \
    " [防火墙] 正在放行 $proto 端口 $port..."

  if command -v firewall-cmd >/dev/null 2>&1 &&
     command systemctl \
       is-active \
       --quiet \
       firewalld \
       2>/dev/null
  then
    if command firewall-cmd \
      --permanent \
      --query-port="$port/$proto" \
      >/dev/null 2>&1
    then
      green \
        " [防火墙] firewalld 已存在 $port/$proto，未接管原规则。"

      return 0
    fi

    if ! command firewall-cmd \
      --permanent \
      --add-port="$port/$proto"
    then
      return 1
    fi

    if ! command firewall-cmd --reload; then
      command firewall-cmd \
        --permanent \
        --remove-port="$port/$proto" \
        >/dev/null 2>&1 || true

      return 1
    fi

    state_line="$(
      printf 'v2|%s|firewalld|inet|%s|%s|-' \
        "$tag" \
        "$proto" \
        "$port"
    )"

    if ! _firewall_state_add "$state_line"; then
      command firewall-cmd \
        --permanent \
        --remove-port="$port/$proto" \
        >/dev/null 2>&1 || true

      command firewall-cmd --reload \
        >/dev/null 2>&1 || true

      return 1
    fi

    return 0
  fi

  if command -v ufw >/dev/null 2>&1 &&
     command ufw status 2>/dev/null |
       grep -q '^Status: active'
  then
    if command ufw status 2>/dev/null |
      grep -Eq \
        "^[[:space:]]*${port}/${proto}([[:space:]]|$).*ALLOW"
    then
      green \
        " [防火墙] UFW 已存在 $port/$proto，未接管原规则。"

      return 0
    fi

    command ufw allow "$port/$proto" ||
      return 1

    state_line="$(
      printf 'v2|%s|ufw|inet|%s|%s|-' \
        "$tag" \
        "$proto" \
        "$port"
    )"

    if ! _firewall_state_add "$state_line"; then
      command ufw \
        --force \
        delete allow "$port/$proto" \
        >/dev/null 2>&1 || true

      return 1
    fi

    return 0
  fi

  _open_iptables_rule \
    iptables \
    ipv4 \
    "$port" \
    "$proto" \
    "$tag"

  _open_iptables_rule \
    ip6tables \
    ipv6 \
    "$port" \
    "$proto" \
    "$tag"

  save_iptables
}

_remove_owned_firewall_rule() {
  local backend="$1"
  local family="$2"
  local proto="$3"
  local port="$4"
  local comment="$5"
  local tool

  case "$backend" in
    firewalld)
      if command -v firewall-cmd >/dev/null 2>&1; then
        command firewall-cmd \
          --permanent \
          --remove-port="$port/$proto" \
          >/dev/null 2>&1 || true

        command firewall-cmd --reload \
          >/dev/null 2>&1 || true
      fi
      ;;

    ufw)
      if command -v ufw >/dev/null 2>&1; then
        command ufw \
          --force \
          delete allow "$port/$proto" \
          >/dev/null 2>&1 || true
      fi
      ;;

    iptables)
      tool="iptables"

      if [[ "$family" == "ipv6" ]]; then
        tool="ip6tables"
      fi

      if command -v "$tool" >/dev/null 2>&1; then
        "$tool" \
          -D INPUT \
          -p "$proto" \
          --dport "$port" \
          -m comment \
          --comment "$comment" \
          -j ACCEPT \
          >/dev/null 2>&1 || true
      fi
      ;;

    *)
      printf \
        '[警告] 未知防火墙后端，未删除规则: %s\n' \
        "$backend" \
        >&2

      return 1
      ;;
  esac
}

close_port_by_tag() {
  local target_tag="${1:-}"
  local tmp_state
  local line
  local version
  local tag
  local backend
  local family
  local proto
  local port
  local comment

  if [[ ! "$target_tag" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf \
      '[错误] 非法防火墙标签: %q\n' \
      "$target_tag" \
      >&2

    return 1
  fi

  [[ -f "$FIREWALL_STATE" ]] ||
    return 0

  tmp_state="$(
    mktemp \
      /etc/sing-box${HY2_INSTANCE_SUFFIX}/.firewall_state.tmp.XXXXXX
  )" || return 1

  chmod 600 "$tmp_state"

  while IFS= read -r line ||
        [[ -n "$line" ]]
  do
    [[ -n "$line" ]] || continue

    # 旧格式 tag:proto:port 无法证明规则归属。
    # 为防止误删管理员规则，仅保留并警告。
    if [[ "$line" != v2\|* ]]; then
      if [[ "$line" == "$target_tag:"* ]]; then
        printf \
          '[警告] 保留旧版防火墙状态记录，因无法证明规则归属: %s\n' \
          "$line" \
          >&2
      fi

      printf '%s\n' "$line" >> "$tmp_state"
      continue
    fi

    IFS='|' read -r \
      version \
      tag \
      backend \
      family \
      proto \
      port \
      comment \
      <<< "$line"

    if [[ "$version" != "v2" ||
          -z "$tag" ||
          -z "$backend" ||
          -z "$family" ||
          -z "$proto" ||
          -z "$port" ]]
    then
      printf \
        '[警告] 保留无法解析的防火墙状态记录: %s\n' \
        "$line" \
        >&2

      printf '%s\n' "$line" >> "$tmp_state"
      continue
    fi

    if [[ "$tag" != "$target_tag" ]]; then
      printf '%s\n' "$line" >> "$tmp_state"
      continue
    fi

    yellow \
      " [防火墙] 正在移除本项目创建的 $proto 端口 $port 规则..."

    if ! _remove_owned_firewall_rule \
      "$backend" \
      "$family" \
      "$proto" \
      "$port" \
      "$comment"
    then
      printf '%s\n' "$line" >> "$tmp_state"
    fi
  done < "$FIREWALL_STATE"

  mv -f "$tmp_state" "$FIREWALL_STATE"
  chmod 600 "$FIREWALL_STATE"

  save_iptables
}

