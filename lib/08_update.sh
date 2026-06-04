#!/usr/bin/env bash
# shellcheck shell=bash

# 9. 脚本在线更新与回滚
# =================================================================

get_raw_base() {
  echo "${REPO_RAW_BASE:-${HY2_VLESS_RAW_BASE:-https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main}}"
}

get_local_version() {
  cat "${INSTALL_DIR:-/opt/hy2-vless-install}/VERSION" 2>/dev/null \
    || cat "${SCRIPT_DIR:-.}/VERSION" 2>/dev/null \
    || echo "dev"
}

get_remote_version() {
  local base
  base="$(get_raw_base)"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --retry 2 "$base/VERSION" 2>/dev/null | head -n1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=10 --tries=2 -O- "$base/VERSION" 2>/dev/null | head -n1
  else
    return 1
  fi
}

version_gt() {
  local newer="$1"
  local older="$2"

  [[ -z "$newer" ]] && return 1
  [[ "$newer" == "$older" ]] && return 1
  [[ "$newer" == "dev" ]] && return 1
  [[ -z "$older" || "$older" == "dev" ]] && return 0

  printf '%s\n%s\n' "$older" "$newer" | sort -V | tail -n1 | grep -qx "$newer"
}

backup_current_script() {
  local install_dir="${INSTALL_DIR:-/opt/hy2-vless-install}"
  local bak_dir="/opt/hy2-vless-install.backup.$(date +%F-%H%M%S)"

  if [[ -d "$install_dir" ]]; then
    cp -a "$install_dir" "$bak_dir"
    echo "$bak_dir"
  fi
}

restore_script_backup() {
  local bak_dir="$1"
  local install_dir="${INSTALL_DIR:-/opt/hy2-vless-install}"

  [[ -z "$bak_dir" || ! -d "$bak_dir" ]] && return 1

  rm -rf "$install_dir"
  cp -a "$bak_dir" "$install_dir"
  chmod +x "$install_dir/install.sh" 2>/dev/null || true
  chmod +x "$install_dir"/lib/*.sh 2>/dev/null || true
}

download_update_file() {
  local url="$1"
  local dest="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=10 --tries=2 -O "$dest" "$url"
  else
    red " [错误] 未找到 curl 或 wget，无法更新。"
    return 1
  fi
}

pause_after_update() {
  echo ""
  echo -en " ${LIGHT_YELLOW}按回车返回主菜单...${PLAIN}"
  read -r _ || true
}


verify_update_checksums() {
  local tmp_dir="$1"
  local sums_file="$tmp_dir/SHA256SUMS"
  local expected
  local target
  local actual
  local failed=0

  if [[ ! -s "$sums_file" ]]; then
    red " [错误] 未找到 SHA256SUMS，已停止更新。"
    return 1
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    red " [错误] 当前系统缺少 sha256sum，无法校验更新文件。"
    return 1
  fi

  yellow " 正在校验更新文件完整性..."

  while read -r expected target _; do
    [[ -z "$expected" || -z "$target" ]] && continue
    [[ "$expected" =~ ^# ]] && continue

    target="${target#./}"

    case "$target" in
      install.sh|VERSION|lib/*.sh)
        ;;
      *)
        continue
        ;;
    esac

    if [[ ! -f "$tmp_dir/$target" ]]; then
      red " [错误] 校验失败，文件缺失: $target"
      failed=1
      continue
    fi

    actual="$(sha256sum "$tmp_dir/$target" | awk '{print $1}')"

    if [[ "$actual" != "$expected" ]]; then
      red " [错误] 校验失败: $target"
      red "        期望: $expected"
      red "        实际: $actual"
      failed=1
    fi
  done < "$sums_file"

  if [[ "$failed" -ne 0 ]]; then
    return 1
  fi

  green " [✔] 更新文件完整性校验通过。"
  return 0
}

self_update() {
  local install_dir="${INSTALL_DIR:-/opt/hy2-vless-install}"
  local base tmp_dir local_ver remote_ver bak_dir m confirm_update

  base="$(get_raw_base)"
  local_ver="$(get_local_version)"
  remote_ver="$(get_remote_version)"

  echo ""
  print_line
  green " 脚本在线更新"
  print_line
  echo ""

  yellow " 当前版本: ${local_ver}"
  yellow " 远程版本: ${remote_ver:-获取失败}"

  if [[ -z "$remote_ver" ]]; then
    red " [错误] 无法获取远程版本，请检查网络或 GitHub raw 地址。"
    pause_after_update
    return 1
  fi

  if ! version_gt "$remote_ver" "$local_ver"; then
    green " [✔] 当前已是最新版本，无需更新。"
    pause_after_update
    return 0
  fi

  echo ""
  echo -en " ${LIGHT_YELLOW} ▶ 检测到新版本 v${remote_ver}，是否立即更新？(y/n) [默认: y]: ${PLAIN}"
  read -r confirm_update || confirm_update="y"
  [[ -z "$confirm_update" ]] && confirm_update="y"

  if [[ "$confirm_update" != "y" && "$confirm_update" != "Y" ]]; then
    yellow " 已取消更新。"
    pause_after_update
    return 0
  fi

  tmp_dir="$(mktemp -d /tmp/hy2-vless-update.XXXXXX)" || {
    red " [错误] 无法创建临时目录。"
    pause_after_update
    return 1
  }

  mkdir -p "$tmp_dir/lib"

  yellow " 正在下载新版入口脚本..."
  if ! download_update_file "$base/install.sh" "$tmp_dir/install.sh"; then
    red " [错误] install.sh 下载失败。"
    rm -rf "$tmp_dir"
    pause_after_update
    return 1
  fi

  yellow " 正在下载新版模块..."
  for m in "${MODULES[@]}"; do
    if ! download_update_file "$base/lib/$m" "$tmp_dir/lib/$m"; then
      red " [错误] 模块下载失败: $m"
      rm -rf "$tmp_dir"
      pause_after_update
      return 1
    fi
  done

  if ! download_update_file "$base/VERSION" "$tmp_dir/VERSION"; then
    echo "$remote_ver" > "$tmp_dir/VERSION"
  fi

  if ! download_update_file "$base/SHA256SUMS" "$tmp_dir/SHA256SUMS"; then
    red " [错误] SHA256SUMS 下载失败，已停止更新。"
    rm -rf "$tmp_dir"
    pause_after_update
    return 1
  fi

  if ! verify_update_checksums "$tmp_dir"; then
    red " [错误] 更新文件完整性校验失败，已停止更新。"
    rm -rf "$tmp_dir"
    pause_after_update
    return 1
  fi

  yellow " 正在执行语法检查..."
  if ! bash -n "$tmp_dir/install.sh"; then
    red " [错误] install.sh 语法检查失败，已停止更新。"
    rm -rf "$tmp_dir"
    pause_after_update
    return 1
  fi

  for m in "$tmp_dir"/lib/*.sh; do
    if ! bash -n "$m"; then
      red " [错误] 模块语法检查失败: $(basename "$m")"
      rm -rf "$tmp_dir"
      pause_after_update
      return 1
    fi
  done

  bak_dir="$(backup_current_script)"
  [[ -n "$bak_dir" ]] && green " [✔] 当前脚本已备份到: $bak_dir"

  yellow " 正在覆盖安装新版脚本..."
  mkdir -p "$install_dir/lib"

  if ! cp -f "$tmp_dir/install.sh" "$install_dir/install.sh" \
    || ! cp -f "$tmp_dir"/lib/*.sh "$install_dir/lib/" \
    || ! cp -f "$tmp_dir/VERSION" "$install_dir/VERSION" \
    || ! cp -f "$tmp_dir/SHA256SUMS" "$install_dir/SHA256SUMS"; then
    red " [错误] 覆盖失败，正在尝试回滚。"
    restore_script_backup "$bak_dir" && green " [✔] 已回滚到更新前版本。"
    rm -rf "$tmp_dir"
    pause_after_update
    return 1
  fi

  chmod +x "$install_dir/install.sh"
  chmod +x "$install_dir"/lib/*.sh 2>/dev/null || true

  cat > /usr/bin/666 <<EOF_WRAPPER
#!/usr/bin/env bash
cd "$install_dir" || exit 1
exec bash "$install_dir/install.sh" "\$@"
EOF_WRAPPER

  chmod +x /usr/bin/666
  rm -rf "$tmp_dir"

  HY2_VLESS_VERSION="$remote_ver"
  export HY2_VLESS_VERSION

  green " [✔] 脚本已成功升级到 v${remote_ver}"
  yellow " 重新输入 666 即可进入新版面板。"
  pause_after_update
}
