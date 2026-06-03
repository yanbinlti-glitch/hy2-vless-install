# 🚀 Hy2 + VLESS Reality 一键安装脚本

<p align="center">
  <img src="https://img.shields.io/badge/Sing--box-Auto%20Install-brightgreen?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Hysteria2-UDP%2FQUIC-blueviolet?style=for-the-badge" />
  <img src="https://img.shields.io/badge/VLESS-Reality-orange?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Linux-success?style=for-the-badge" />
</p>

<p align="center">
  <b>一个现代化、交互式、支持 Hy2 / VLESS Reality 双协议的 Sing-box 一键部署与管理脚本</b>
</p>

---

## ✨ 项目简介

本脚本用于在 VPS 上快速部署并管理 **Sing-box 节点服务**，支持：

* ⚡ **Hysteria 2**
* 🛡️ **VLESS + Reality**
* 🌐 **Nginx 聚合订阅**
* 📱 **二维码订阅**
* 🔥 **BBR / TCP Fast Open / UDP 优化**
* 🧩 **Clash Meta / Mihomo / Sing-box 客户端配置导出**
* 🛠️ **一键诊断、修复、卸载、重启**

首次运行后，脚本会自动创建快捷命令：

```bash
666
```

以后只需要输入 `666` 即可进入管理面板。

---

## 🚀 一键安装

> 推荐使用 `root` 用户执行。

```bash
wget -4 -O install.sh https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main/install.sh && chmod +x install.sh && bash install.sh
```

---

## 🖥️ 支持系统

| 系统          |   状态 | 包管理器  |
| ----------- | ---: | ----- |
| Debian      | ✅ 支持 | `apt` |
| Ubuntu      | ✅ 支持 | `apt` |
| CentOS      | ✅ 支持 | `yum` |
| RHEL        | ✅ 支持 | `yum` |
| AlmaLinux   | ✅ 支持 | `yum` |
| Rocky Linux | ✅ 支持 | `yum` |
| Fedora      | ✅ 支持 | `yum` |
| Alpine      | ✅ 支持 | `apk` |

---

## 📦 支持架构

| 架构      | 状态 |
| ------- | -: |
| `amd64` |  ✅ |
| `arm64` |  ✅ |
| `armv7` |  ✅ |
| `386`   |  ✅ |
| `s390x` |  ✅ |

---

## 🎯 核心功能

| 功能               | 说明                                             |
| ---------------- | ---------------------------------------------- |
| 自动环境检测           | 自动识别系统并配置安装命令                                  |
| 自动换源保护           | 默认源异常时自动切换镜像源                                  |
| 自动安装依赖           | 自动安装 `curl`、`wget`、`jq`、`nginx`、`qrencode` 等依赖 |
| 自动拉取核心           | 自动下载并安装 Sing-box 核心                            |
| Hy2 节点部署         | 支持 Hysteria 2，适合 UDP / QUIC 场景                 |
| VLESS Reality 部署 | 支持 Reality、Vision、X25519、Short ID              |
| 聚合订阅             | 自动生成 Clash Meta / Sing-box / Base64 订阅         |
| 二维码输出            | 自动生成订阅二维码                                      |
| 防火墙管理            | 自动放行和清理相关端口                                    |
| 出口代理             | 支持 SOCKS5 落地代理与流媒体分流                           |
| 系统加速             | 支持 BBR、TCP Fast Open、UDP 缓冲区优化                 |
| 一键卸载             | 支持节点卸载和全局清理                                    |

---

## 🧭 主菜单预览

运行脚本后会进入如下管理菜单：

```text
[1] 安装部署 节点核心 (Hysteria 2 / VLESS)
[2] 节点安全卸载与清理管控

[3] 启动 / 停止 / 重启服务
[4] 查看 / 修改 配置文件
[5] 配置 出口落地代理与分流

[6] 获取 节点配置 与 订阅链接
[7] 开启 BBR / TCP Fast Open / UDP 加速
[8] 全局卸载脚本
[9] 一键兼容修复 / 状态诊断

[0] 退出脚本
```

---

## 🧩 协议说明

### ⚡ Hysteria 2

适合弱网、高延迟、丢包环境。

特点：

* 基于 UDP / QUIC
* 支持自签 TLS
* 支持 Salamander 混淆
* 连接速度快
* 抗丢包能力强

安装时需要放行：

```text
UDP 主端口
```

---

### 🛡️ VLESS + Reality

适合 TCP 场景和高伪装需求。

脚本会自动生成：

* UUID
* Reality Keypair
* Public Key
* Private Key
* Short ID
* Vision Flow
* Chrome 指纹
* TCP Fast Open

安装时需要放行：

```text
TCP 主端口
```

默认端口为：

```text
443
```

也可以在安装时自定义。

---

## 🌐 订阅说明

脚本会自动部署 Nginx 订阅服务，订阅地址格式如下：

```text
http://服务器IP:订阅端口/订阅路径
```

生成目录：

```text
/var/www/sing-box/
```

常见文件：

| 文件                    | 说明                     |
| --------------------- | ---------------------- |
| `url.txt`             | 原始节点链接                 |
| `sub_b64.txt`         | Base64 通用订阅            |
| `clash-meta-sub.yaml` | Clash Meta / Mihomo 配置 |
| `sing-box.json`       | Sing-box 客户端配置         |
| `sub_qr.png`          | 订阅二维码图片                |
| `sub_qr.txt`          | 终端二维码文本                |

---

## 📱 客户端适配

脚本会根据客户端 User-Agent 自动返回对应订阅格式：

| 客户端             | 返回格式   |
| --------------- | ------ |
| Clash Meta      | YAML   |
| Mihomo          | YAML   |
| Clash Verge     | YAML   |
| Stash           | YAML   |
| Sing-box        | JSON   |
| SFA / SFI / SFM | JSON   |
| 其他客户端           | Base64 |

---

## 🔥 系统加速

进入菜单：

```text
[7] 开启 BBR / TCP Fast Open / UDP 加速
```

可优化：

* BBR 拥塞控制
* TCP Fast Open
* TCP MTU Probing
* UDP 缓冲区
* 系统连接队列
* 文件描述符限制

> 部分 OpenVZ / LXC / 低版本内核可能无法开启 BBR。

---

## 🛠️ 常用命令

### 启动管理面板

```bash
666
```

### 查看 Sing-box 状态

```bash
systemctl status sing-box
```

Alpine：

```bash
rc-service sing-box status
```

### 查看 Sing-box 日志

```bash
journalctl -u sing-box -n 80 --no-pager
```

Alpine：

```bash
tail -n 80 /var/log/sing-box.log
```

### 检查配置文件

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

### 查看监听端口

```bash
ss -lntup
```

---

## 📁 重要路径

| 路径                           | 说明          |
| ---------------------------- | ----------- |
| `/usr/bin/666`               | 快捷启动命令      |
| `/usr/local/bin/sing-box`    | Sing-box 核心 |
| `/etc/sing-box/config.json`  | 主配置文件       |
| `/etc/sing-box/cert.crt`     | 自签证书        |
| `/etc/sing-box/private.key`  | 私钥          |
| `/etc/sing-box/sub_port.txt` | 订阅端口        |
| `/etc/sing-box/sub_path.txt` | 订阅路径        |
| `/var/www/sing-box/`         | 订阅文件目录      |
| `/etc/nginx/`                | Nginx 配置目录  |

---

## 🧹 卸载说明

### 卸载单个节点

进入菜单：

```text
[2] 节点安全卸载与清理管控
```

可选择：

* 仅卸载 Hysteria 2
* 仅卸载 VLESS Reality
* 卸载全部节点与订阅服务，但保留 Sing-box 核心

---

### 全局卸载

进入菜单：

```text
[8] 全局卸载脚本
```

会清理：

* Sing-box 核心
* 节点配置
* 订阅服务
* Nginx 订阅配置
* 防火墙记录
* 快捷命令 `666`
* 旧快捷命令 `hy2`

---

## 🧯 故障排查

### 订阅打不开

请检查：

```bash
nginx -t
systemctl status nginx
ss -lntup | grep nginx
```

并确认云厂商安全组已放行订阅 TCP 端口。

---

### Hy2 无法连接

请检查：

* UDP 端口是否放行
* 云厂商安全组是否放行 UDP
* 客户端密码是否正确
* Salamander 混淆参数是否一致
* VPS 是否支持 UDP 转发

---

### VLESS Reality 无法连接

请检查：

* TCP 端口是否放行
* UUID 是否正确
* Public Key 是否正确
* Short ID 是否正确
* SNI 是否一致
* 客户端是否启用 Reality / Vision

---

### Sing-box 启动失败

执行：

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

查看日志：

```bash
journalctl -u sing-box -n 80 --no-pager
```

---

## 🧪 一键诊断

进入菜单：

```text
[9] 一键兼容修复 / 状态诊断
```

该功能会自动执行：

* Sing-box 核心检查
* DNS 旧配置迁移
* DNS detour 修复
* 路由规则兼容修复
* IPv6 监听修复
* 配置校验
* 服务重启
* 订阅文件重建
* Nginx 配置测试
* 端口监听检查

---

## ⚠️ 安全提示

> 请妥善保存节点链接、订阅地址、UUID、密码、Reality 密钥等敏感信息。

建议：

* 不要公开订阅链接
* 定期更换订阅路径
* 定期更换节点密码
* 只开放必要端口
* 使用强密码
* 不要将脚本用于非法用途

---

## 📜 免责声明

本项目仅用于学习、研究与个人服务器管理。
使用者需自行承担使用风险，并遵守所在国家或地区的法律法规。
项目作者不对任何滥用行为及其后果负责。

---

## ⭐ Star 支持

如果这个项目对你有帮助，欢迎点一个 Star。

```text
Hy2 + VLESS Reality 一键安装脚本
```
