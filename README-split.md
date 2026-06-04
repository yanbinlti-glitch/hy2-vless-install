# Hy2 + VLESS Reality 一键安装脚本（模块化版）

这个版本把原来的超长 `install.sh` 拆成了入口文件和多个 `lib/` 模块，便于维护，同时保留 `666` 快捷命令。

## 文件结构

```text
install.sh
lib/
  00_ui.sh
  01_system.sh
  02_service_firewall.sh
  03_env_core.sh
  04_install_nodes.sh
  05_subscription.sh
  06_panel_tools.sh
  07_menu.sh
```

## 运行方式

### 方式一：克隆仓库后运行

```bash
git clone https://github.com/yanbinlti-glitch/hy2-vless-install.git
cd hy2-vless-install
chmod +x install.sh
bash install.sh
```

### 方式二：继续保留原来的一键运行习惯

入口 `install.sh` 支持在缺少 `lib/` 时自动从 GitHub raw 地址拉取模块。

```bash
wget -4 -O install.sh https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main/install.sh && chmod +x install.sh && bash install.sh
```

## 说明

模块化后，`666` 不再复制单个脚本文件，而是：

1. 把 `install.sh` 和 `lib/` 一起安装到 `/opt/hy2-vless-install/`
2. 创建 `/usr/bin/666` 包装器
3. 后续输入 `666` 时执行 `/opt/hy2-vless-install/install.sh`

这样可以避免多文件拆分后快捷命令找不到模块的问题。
