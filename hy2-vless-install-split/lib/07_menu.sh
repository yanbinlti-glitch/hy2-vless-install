#!/usr/bin/env bash
# shellcheck shell=bash

#  8. 主菜单控制
# =================================================================
menu() {
    local status_ui="${LIGHT_RED}● 未运行 / 异常${PLAIN}"
    is_svc_active sing-box && status_ui="${LIGHT_GREEN}● 运行中 (Active)${PLAIN}"

    clear
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "${LIGHT_GREEN}  ██████╗  ██╗   ██╗ ██████╗  ██╗       █████╗ ${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██╔══██╗ ██║   ██║ ██╔═══██╗██║      ██╔══██╗${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ███████║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ██╔══██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██████╔╝ ╚██████╔╝ ╚██████╔╝███████╗ ██║  ██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ╚═════╝   ╚══════╝  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝  ${LIGHT_YELLOW}[当前状态: ${status_ui}${LIGHT_YELLOW}]${PLAIN}"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e " ${LIGHT_GREEN}项目名称 ：Sing-box (Hy2 / VLESS) 一键部署与管理脚本 (Nginx订阅加强版)${PLAIN}"
    echo -e " ${LIGHT_PURPLE}项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch${PLAIN}"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    yellow " 脚本快捷方式：666 (已自动配置，下次可在终端直接输入 666 启动)"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 节点核心 (Hysteria 2 / VLESS)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}节点安全卸载与清理管控${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_GREEN}配置 出口落地代理与分流 (IP 检测 & 流媒体解锁)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_PURPLE}开启 BBR / TCP Fast Open / UDP 加速 (强烈推荐)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_RED}全局卸载脚本 (回归没装脚本的状态)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_YELLOW}一键兼容修复 / 状态诊断 (推荐排障)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-9]: ${PLAIN}"
    read menuInput || exit 1
    
    case $menuInput in
        1 ) inst_singbox ;;
        2 ) remove_node ;;
        3 ) singbox_switch ;;
        4 ) edit_config ;;
        5 ) config_outbound ;;
        6 ) showconf ;;
        7 ) enable_bbr ;;
        8 ) global_uninstall ;;
        9 ) quick_repair_and_status ;;
        0 ) exit 0 ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}
