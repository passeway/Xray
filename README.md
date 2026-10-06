<div align="center">

# Xray

**Deployment & Service Management**

面向 Linux 的 Xray 部署与管理工具。<br>
从内核安装到客户端连接，在一个终端入口完成。

[![Checks](https://github.com/passeway/Xray/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Xray/actions/workflows/check.yml)
[![Xray Core](https://img.shields.io/badge/Xray-Core-18181b?style=flat-square)](https://github.com/XTLS/Xray-core)
![Platform](https://img.shields.io/badge/Linux-AMD64%20%7C%20ARM64-52525b?style=flat-square)
[![License](https://img.shields.io/github/license/passeway/Xray?style=flat-square&color=52525b)](LICENSE)

[快速开始](#快速开始) · [连接配置](#连接配置) · [运维指南](#运维指南) · [技术参考](#技术参考)

</div>

---

## 概览

Xray 将 VLESS + REALITY、Shadowsocks 2022 的部署与 systemd 服务管理整合到一个交互式脚本中。一次安装生成 TCP + Vision、XHTTP 与 SS2022 三组入站，并导出可直接导入客户端的分享链接。

- **三组连接配置** — TCP + Vision、XHTTP 与 SS2022，分别使用独立端口。
- **内核校验** — 下载官方发行包并验证 SHA256；更新前使用新内核检查现有配置。
- **自动连接信息** — 生成 UUID、REALITY 密钥、SS2022 密钥、short-id 与 XHTTP 路径，根据公网 IP 的两位国家/地区代码自动命名节点。
- **统一运维入口** — 管理服务状态、实时日志、内核更新与客户端链接导出。

## 快速开始

### 环境要求

| 项目 | 支持范围 |
| :--- | :--- |
| 操作系统 | 使用 systemd 的 Debian / Ubuntu、RHEL / Fedora 系 Linux |
| 处理器架构 | AMD64、ARM64 |
| 执行环境 | root 权限，已安装 `bash` 与 `curl` |
| 客户端 | 支持所选协议的客户端与内核；SS2022 需支持 AES-128-GCM 2022 |

依赖通过 `apt-get`、`dnf` 或 `yum` 按需安装。当前未适配 Alpine / OpenRC。

### 安装

```bash
bash <(curl -fsSL https://xray-bay.vercel.app)
```

1. 选择 **1 · 安装 Xray 服务**，自动生成三组节点。
2. 在云安全组和服务器防火墙中放行两组 VLESS 的 TCP 端口，以及 SS2022 的 TCP/UDP 端口。
3. 将输出的 `vless://` 或 `ss://` 链接导入客户端。

节点名称前缀自动使用服务器公网 IP 的两位大写国家/地区代码，如 `US`、`JP`、`HK`，无需输入确认。导出名称示例：`US-vless-tcp`、`US-vless-xhttp`、`US-ss2022`。地区查询失败时保留已有名称；新安装回退到公网 IP。

> [!NOTE]
> 检测到已有程序、配置或服务时，脚本会阻止重复安装。已有安装请使用菜单 **9** 更新内核。

## 连接配置

新安装默认启用以下三组节点，各使用一个独立的随机端口。

| 参数 | VLESS · TCP + Vision | VLESS · XHTTP | Shadowsocks 2022 |
| :--- | :--- | :--- | :--- |
| 加密 / 安全 | REALITY | REALITY | `2022-blake3-aes-128-gcm` |
| 放行端口 | TCP | TCP | TCP + UDP |
| 认证 | UUID + REALITY 密钥 | UUID + REALITY 密钥 | 独立 16 字节预共享密钥 |
| Flow | `xtls-rprx-vision` | 留空 | 不适用 |
| 路径 | 不适用 | 随机生成 | 不适用 |
| 模式 | — | `auto` | — |
| 默认 SNI | `www.ua.edu` | `www.ua.edu` | 不适用 |
| 分享链接 | `vless://` | `vless://` | `ss://` |
| 名称示例 | `US-vless-tcp` | `US-vless-xhttp` | `US-ss2022` |

两组 VLESS 入站共用本次生成的 UUID、REALITY 密钥对与 short-id。客户端参数应与对应入站保持一致，XHTTP 还需核对路径。

SS2022 密钥独立生成，以 Base64 保存；其端口同时监听 TCP 和 UDP。客户端须支持 `2022-blake3-aes-128-gcm`，无需配置 REALITY、SNI 或 Vision Flow。

### XHTTP 参数选择

当前配置面向直连 REALITY：保留随机 `path` 与 `mode=auto`，Flow 留空。客户端和服务端路径须一致。按[官方指南](https://github.com/XTLS/Xray-core/discussions/4113)，通常只需配置路径，其余使用默认值。

不额外固定 `host`、XMUX 并发数或缓冲区参数；这些参数应在有明确网络瓶颈或 CDN/反代需求时调整。当前 REALITY 配置不应直接改为 H3；H3 需要另行配置 QUIC/TLS。

### 导出与同步

选择菜单 **8**，根据当前服务端配置重新生成客户端链接。查看已保存的链接：

```bash
cat /usr/local/etc/xray/config.txt
```

修改服务端配置后，先选择 **5** 重启服务，再选择 **8** 导出并重新导入客户端。导出时会查询 IP 国家/地区代码并更新节点前缀；IPv6 地址自动使用带方括号的链接格式。

## 运维指南

重新运行安装命令，即可进入管理菜单。

| 选项 | 功能 | 行为 |
| :---: | :--- | :--- |
| `1` | 安装服务 | 下载内核、生成三组节点并启用服务 |
| `2` | 卸载服务 | 确认后删除服务与配置 |
| `3` | 启动服务 | 校验配置并启动；已运行时会重启 |
| `4` | 停止服务 | 停止当前服务 |
| `5` | 重启服务 | 校验配置后重启 |
| `6` | 检查状态 | 查看 systemd 服务状态 |
| `7` | 查看日志 | 跟踪实时日志，`Ctrl+C` 返回 |
| `8` | 查看配置 | 重新生成并显示客户端分享链接 |
| `9` | 更新内核 | 校验新内核、替换并重启服务 |
| `0` | 退出 | 退出管理工具 |

### 更新行为

菜单 **9** 仅更新内核，保留现有端口、UUID、密钥及服务端配置，沿用原服务运行用户。旧安装不会因更新内核自动增加 SS2022；菜单 **8** 仅导出现有入站的链接。安装只补齐所需依赖，不执行整机软件升级。

脚本不创建备份，也不提供自动回滚。新内核在替换前须通过配置校验；替换后的重启若失败，脚本会报告错误并保留日志供排查。

<details>
<summary><strong>常用 systemd 命令</strong></summary>

```bash
# 服务控制
systemctl start xray
systemctl stop xray
systemctl restart xray

# 状态与日志
systemctl status xray --no-pager
journalctl -u xray -n 50 --no-pager
journalctl -u xray -f
```

</details>

## 技术参考

### 文件布局

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/xray` | Xray 内核 |
| `/usr/local/etc/xray/config.json` | 服务端配置 |
| `/usr/local/etc/xray/config.txt` | 客户端分享链接 |
| `/usr/local/etc/xray/client-meta.json` | 公网地址与节点名称前缀 |
| `/usr/local/share/xray` | 内核资源文件 |
| `/etc/systemd/system/xray.service` | systemd 服务单元 |

### 运行权限

新安装使用独立的 `xray` 服务用户。配置目录权限为 `750`，服务端配置为 `640`，由 root 与服务运行组访问；客户端链接和地址元数据文件权限为 `600`。

REALITY 私钥留在服务端，客户端链接仅包含对应公钥。地区命名通过 `ipwho.is` 查询服务器公网 IP，不影响协议参数。

### 验证范围

仓库 CI 在 Debian、Ubuntu 与 Rocky Linux 容器中检查脚本语法、失败处理和配置导出，并使用官方内核验证 TCP + Vision、XHTTP 与 SS2022 的 TCP 代理流量。

SS2022 原生 UDP 还需实际网络验证。容器测试不覆盖真实 VPS 的 systemd 开机自启与 ARM64 实机运行。

## 故障排查

| 现象 | 检查项 |
| :--- | :--- |
| 服务无法启动 | systemd 状态、配置校验结果与服务日志 |
| 客户端连接超时 | 监听端口、云安全组、服务器防火墙 |
| REALITY 握手失败 | UUID、公钥、short-id 与 SNI |
| TCP 可用，XHTTP 不可用 | 客户端内核支持、XHTTP 路径、Flow 是否留空 |
| SS2022 无法连接 | 客户端是否支持指定加密方式、密钥和端口是否一致 |\n| SS2022 TCP 可用，UDP 不可用 | 同端口 UDP 放行情况、客户端 UDP 支持与网络连通性 |\n| 客户端仍显示旧配置 | 使用菜单 **8** 重新导出，再导入客户端 |

提交问题时，请附上操作系统、Xray 版本、客户端名称与版本，以及隐藏凭据后的相关日志。

[提交 Issue](https://github.com/passeway/Xray/issues) · [查看 CI](https://github.com/passeway/Xray/actions/workflows/check.yml)

---

本项目为独立的安装与管理工具，基于 [XTLS/Xray-core](https://github.com/XTLS/Xray-core)。官方安装项目见 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)，许可证见 [LICENSE](LICENSE)。
