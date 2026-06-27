#!/usr/bin/env bash
# 一键安装脚本 - V1.8.36 稳定版

# 强制加载所有依赖模块
for file in lib/*.sh; do
    [ -f "$file" ] && source "$file"
done

while true; do
    export HY2_INSTANCE_ID="1"
    export HY2_INSTANCE_SUFFIX=""

    clear
    printf "\n\033[1;36m==================================================================================\033[0m\n"
    printf "       👥 请选择要管理的 Sing-box 实例分身        \n"
    printf "\033[1;36m==================================================================================\033[0m\n"
    printf "    \033[1;32m[1]\033[0m 部署/管理 \033[1;33m实例本尊\033[0m (Instance 1, 默认环境)\n"
    printf "    \033[1;32m[2]\033[0m 部署/管理 \033[1;35m实例分身\033[0m (Instance 2, 完全独立的端口与进程)\n"
    printf "    \033[1;32m[8]\033[0m \033[1;36m在线更新 / 检查面板脚本\033[0m\n"
    printf "    \033[1;32m[0]\033[0m \033[1;31m退出控制台\033[0m\n"
    printf "  \033[1;33m▶\033[0m 请输入选项 [0-2, 8] (默认1): "
    read instance_choice
    
    case "$instance_choice" in
        2)
            export HY2_INSTANCE_ID="2"
            export HY2_INSTANCE_SUFFIX="_2"
            break
            ;;
        8)
            self_update
            ;;
        0)
            exit 0
            ;;
        *)
            export HY2_INSTANCE_ID="1"
            export HY2_INSTANCE_SUFFIX=""
            break
            ;;
    esac
done

# 进入主菜单循环
while true; do
    menu
done
