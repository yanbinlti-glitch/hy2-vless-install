# Sing-box (Hy2 / VLESS) 一键部署与管理脚本

基于最新版 Sing-box 核心构建的极简、高效、防封锁的高级代理节点部署与管理脚本。原生支持双协议矩阵，内置 Nginx 智能订阅分发引擎与动态防护架构。

## ⚙️ 核心架构与技术特性

*   **双核协议矩阵**：
    *   **Hysteria 2**：基于 UDP/QUIC 协议，支持端口跳跃（Port Hopping）与 Salamander 混淆，抗丢包极速网络底座。
    *   **VLESS + Reality**：基于 TCP/XTLS-Vision，原生生成 x25519 密钥对与 Short ID，提供强力指纹伪装与抗阻断能力。
*   **JSON 结构化防御**：废弃易错的 YAML 字符串拼接，底层配置全面采用 `jq` 工具进行安全的 JSON 节点注入，杜绝缩进与语法引发的核心崩溃。
*   **自适应全静默伪装**：剥离复杂的域名与 ACME 证书依赖，内置系统级 OpenSSL 自动签发 Bing/Apple/Microsoft 伪装证书。
*   **智能订阅分发 (Nginx)**：自动挂载 Nginx Web 服务，根据安装协议动态下发 `hy2://` 或 `vless://` 链接，并智能适配 Clash Meta (Mihomo) 客户端 YAML 配置。
*   **极限性能调优**：集成 BBR 拥塞控制算法与 UDP 极限并发内核级参数优化机制。
*   **动态落地与分流**：支持一键接入 SOCKS5 中转落地节点，内置针对 Netflix、OpenAI 等流媒体与 AI 平台的智能分流路由策略。

## 💻 系统环境支持

*   **架构**：`amd64` (x86_64), `arm64` (aarch64), `s390x`
*   **操作系统**：Debian, Ubuntu, Alpine, CentOS, AlmaLinux, RockyLinux, Fedora (需 `root` 权限)

## 🚀 安装与运行

以 `root` 用户登录您的 VPS，执行以下命令进行一键部署：

```bash
wget -O install.sh https://raw.githubusercontent.com/yanbinlti-glitch/hy2-vless-install/main/install.sh && chmod +x install.sh && bash install.sh
