self_update() {
    clear
    print_line
    green " 检查 / 在线更新脚本 (多开智能同步版) "
    print_line
    echo ""
    
    local local_version="${HY2_VLESS_VERSION:-未知}"
    # 读取 Github 远端版本号
    local remote_version=$(curl -sL --max-time 5 "https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main/VERSION" | tr -d '\r\n')
    [[ -z "$remote_version" ]] && remote_version="获取失败"

    printf "%b\n" " 当前版本: ${LIGHT_GREEN}${local_version}${PLAIN}"
    printf "%b\n" " 最新版本: ${LIGHT_CYAN}${remote_version}${PLAIN}"
    echo ""
    
    # 智能更新策略判定
    if [[ -z "$HY2_CLONE_NAME" ]]; then
        yellow " ▶ 当前环境: [本体 (Main)]"
        yellow " ▶ 更新策略: 将同时更新本体，并自动将最新纯净代码转码辐射至【所有已存在的分身】！"
    else
        yellow " ▶ 当前环境: [分身 ($HY2_CLONE_NAME)]"
        yellow " ▶ 更新策略: 仅更新当前分身，完全沙盒物理隔离，不影响本体及其他实例。"
    fi
    echo ""
    printf "%b" " ${LIGHT_YELLOW}▶ 是否拉取最新代码并强制更新？(y/n) [默认: y]: ${PLAIN}"
    read update_choice
    [[ "$update_choice" == "n" || "$update_choice" == "N" ]] && return 0

    yellow " 正在从云端拉取最新代码包..."
    
    local dl_tmp="/tmp/hy2_dl_tmp"
    local tmp_base="/tmp/hy2_vless_update_base"
    rm -rf "$dl_tmp" "$tmp_base"
    mkdir -p "$dl_tmp" "$tmp_base"
    
    # 使用 tar.gz 打包拉取，比单文件遍历更快更安全
    if ! curl -sL "https://github.com/yanbinlti-glitch/hy2-vless-install/archive/refs/heads/main.tar.gz" | tar -xz -C "$dl_tmp"; then
        red " [错误] 代码拉取失败，请检查网络！"
        read -p " ▶ 按回车键返回..." temp; return 1
    fi
    
    cp -a "$dl_tmp"/hy2-vless-install-main/. "$tmp_base/" 2>/dev/null || cp -a "$dl_tmp"/. "$tmp_base/"
    rm -rf "$dl_tmp"
    
    # 强制净化跨平台回车符污染
    find "$tmp_base" -type f -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null
    [ -f "$tmp_base/VERSION" ] && sed -i 's/\r$//' "$tmp_base/VERSION"
    
    if [[ -n "$HY2_CLONE_NAME" ]]; then
        yellow " 正在将更新文件转码适配至当前分身 $HY2_CLONE_NAME ..."
        apply_clone_transform "$HY2_CLONE_NAME" "$tmp_base"
        cp -af "$tmp_base/." "/opt/hy2-vless-install_${HY2_CLONE_NAME}/"
        green " [✔] 分身 $HY2_CLONE_NAME 独立更新成功！"
    else
        yellow " 正在更新本体 (Main)..."
        cp -af "$tmp_base/." "/opt/hy2-vless-install/"
        green " [✔] 本体更新成功！"
        
        # 集群联动：扫描并同步更新所有分身
        for dir in /opt/hy2-vless-install_*; do
            if [[ -d "$dir" && -f "$dir/install.sh" ]]; then
                local cname="${dir#/opt/hy2-vless-install_}"
                yellow " 发现分身: $cname，正在自动编译并同步更新..."
                local c_tmp="/tmp/hy2_update_clone_${cname}"
                rm -rf "$c_tmp"
                cp -a "$tmp_base" "$c_tmp"
                apply_clone_transform "$cname" "$c_tmp"
                cp -af "$c_tmp/." "$dir/"
                rm -rf "$c_tmp"
                green "   └─ [✔] 分身 $cname 同步更新完成！"
            fi
        done
    fi
    
    rm -rf "$tmp_base"
    green " [✔] 全局在线更新完毕！即将在 3 秒后热重载面板..."
    sleep 3
    if [[ -n "$HY2_CLONE_NAME" ]]; then
        exec bash "/opt/hy2-vless-install_${HY2_CLONE_NAME}/install.sh"
    else
        exec bash "/opt/hy2-vless-install/install.sh"
    fi
}
