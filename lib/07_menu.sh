run_check_env() {
    check_env
    echo ""
    printf "%b" " ${LIGHT_YELLOW} ▶ 前置依赖与核心安装完成，按回车键返回主菜单...${PLAIN}"
    read temp
}

menu() {
  local status_ui="${LIGHT_RED}● 未运行 / 异常${PLAIN}"
  local version_ui="${HY2_VLESS_VERSION:-dev}"

  is_svc_active sing-box && status_ui="${LIGHT_GREEN}● 运行中 (Active)${PLAIN}"

  clear

  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  printf "%b\n" "${LIGHT_GREEN}  ██████╗  ██╗   ██╗ ██████╗  ██╗       █████╗ ${PLAIN}"
  printf "%b\n" "${LIGHT_GREEN}  ██╔══██╗ ██║   ██║ ██╔═══██╗██║      ██╔══██╗${PLAIN}"
  printf "%b\n" "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ███████║${PLAIN}"
  printf "%b\n" "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ██╔══██║${PLAIN}"
  printf "%b\n" "${LIGHT_GREEN}  ██████╔╝ ╚██████╔╝ ╚██████╔╝███████╗ ██║  ██║${PLAIN}"
  printf "%b\n" "${LIGHT_GREEN}  ╚═════╝   ╚══════╝  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝  ${LIGHT_YELLOW}[当前状态: ${status_ui}${LIGHT_YELLOW}]${PLAIN}"
  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  printf "%b\n" " ${LIGHT_YELLOW}当前版本 ：v${version_ui}${PLAIN}"
  
  local panel_title="Sing-box (Hy2 / VLESS / TUIC) 一键部署与管控面板"
  [[ -n "$HY2_CLONE_NAME" ]] && panel_title="$panel_title ${LIGHT_CYAN}[分身: $HY2_CLONE_NAME]${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}项目名称 ：${panel_title}${PLAIN}"
  
  printf "%b\n" " ${LIGHT_PURPLE}项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch${PLAIN}"
  green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  main_realtime_status_panel
  
  local current_shortcut="666"
  [[ -n "$HY2_CLONE_NAME" ]] && current_shortcut="666_${HY2_CLONE_NAME}"
  yellow " 脚本快捷方式：$current_shortcut (下次可在终端直接输入 $current_shortcut 启动)"

  main_status_show_node_info

  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

  printf "%b\n" " ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_CYAN}安装前置系统依赖与 Sing-box 核心 (首次部署必点)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_GREEN}安装部署 节点协议 (Hy2 / VLESS / TUIC)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_CYAN}WARP IPv6 域名分流${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_GREEN}节点多开分身管控 (创建/切换/监控)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[10]${PLAIN} ${LIGHT_CYAN}检查 / 在线更新脚本${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[11]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[12]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
  printf "%b\n" " ${LIGHT_GREEN}[13]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
  echo "----------------------------------------------------------------------------------"
  printf "%b\n" " ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出控制面板${PLAIN}"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo ""
  printf "%b" " ${LIGHT_YELLOW} ▶ 请输入选项 [0-13]: ${PLAIN}"

  read menuInput || exit 1

  case $menuInput in
      0 ) exit 0 ;;
      1 ) run_check_env ;;
      2 ) inst_singbox ;;
      3 ) remove_node ;;
      4 ) singbox_switch ;;
      5 ) config_modify_menu ;;
      6 ) warp_ipv6_route_menu ;;
      7 ) instance_manager ;;
      8 ) config_outbound ;;
      9 ) showconf ;;
      10 ) self_update ;;
      11 ) enable_bbr ;;
      12 ) quick_repair_and_status ;;
      13 ) global_uninstall ;;
      * ) red " 输入无效"; sleep 1 ;;
  esac
}
