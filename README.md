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

Xray 将 VLESS + REALITY 的安装、配置与 systemd 服务管理整合到一个交互式脚本中。一次安装生成 TCP + Vision 与 XHTTP 两组入站，并导出可直接导入客户端的分享链接。

- **双传输配置** — 同时部署 TCP + Vision 和 XHTTP，分别使用独立端口。
- **内核校验** — 下载官方发行包并验证 SHA256；更新前使用新内核检查现有配置。
- **自动连接信息** — 生成 UUID、REALITY 密钥、short-id 与 XHTTP 路径，根据公网 IP 地区自动命名节点。
- **统一运维入口** — 管理服务状态、实时日志、内核更新与客户端链接导出。

## 快速开始

### 环境要求

| 项目 | 支持范围 |
| :--- | :--- |
| 操作系统 | 使用 systemd 的 Debian / Ubuntu、RHEL / Fedora 系 Linux |
| 处理器架构 | AMD64、ARM64 |
| 执行环境 | root 权限，已安装 `bash` 与 `curl` |
| 客户端 | 支持对应传输方式及 REALITY 的客户端与内核 |

依赖通过 `apt-get`、`dnf` 或 `yum` 按需安装。当前未适配 Alpine / OpenRC。

### 安装

```bash
bash <(curl -fsSL https://xray-bay.vercel.app)
```

1. 选择 **1 · 安装 Xray 服务**。
2. 在云安全组和服务器防火墙中放行生成的两个 TCP 端口。
3. 将输出的 `vless://` 链接导入客户端。

节点名称前缀自动取自服务器公网 IP 的国家/地区与城市，无需输入确认。地区查询失败时保留已有名称；新安装回退到公网 IP。

> [!NOTE]
> 检测到已有程序、配置或服务时，脚本会阻止重复安装。已有安装请使用菜单 **9** 更新内核。

## 连接配置

两组入站均使用 VLESS + REALITY，共用本次生成的 UUID、REALITY 密钥对与 short-id。

| 参数 | TCP + Vision | XHTTP |
| :--- | :--- | :--- |
| 传输方式 | `tcp` | `xhttp` |
| Flow | `xtls-rprx-vision` | 留空 |
| 监听端口 | 随机生成 | 随机生成，与 TCP 入站不同 |
| 路径 | 无 | 随机生成 |
| 模式 | — | `auto` |
| 默认 SNI | `www.ua.edu` | `www.ua.edu` |

以实际导出的链接为准。客户端的地址、端口、UUID、公钥、short-id 与 SNI 必须匹配对应入站；XHTTP 还需核对路径。

### 导出与同步

选择菜单 **8**，根据当前服务端配置重新生成客户端链接。查看已保存的链接：

```bash
cat /usr/local/etc/xray/config.txt
```

修改服务端配置后，先选择 **5** 重启服务，再选择 **8** 导出并重新导入客户端。导出时会查询 IP 地区并更新节点前缀；IPv6 地址自动使用带方括号的链接格式。

## 运维指南

重新运行安装命令，即可进入管理菜单。

| 选项 | 功能 | 行为 |
| :---: | :--- | :--- |
| `1` | 安装服务 | 下载内核、生成配置并启用服务 |
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

更新保留现有端口、UUID、密钥及服务端配置，沿用原服务运行用户。安装只补齐所需依赖，不执行整机软件升级。

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

仓库 CI 在 Debian、Ubuntu 与 Rocky Linux 容器中检查脚本语法、失败处理和配置导出，并使用官方内核验证 TCP / XHTTP 代理流量。

容器测试不覆盖真实 VPS 的 systemd 开机自启与 ARM64 实机运行。

## 故障排查

| 现象 | 检查项 |
| :--- | :--- |
| 服务无法启动 | systemd 状态、配置校验结果与服务日志 |
| 客户端连接超时 | 监听端口、云安全组、服务器防火墙 |
| REALITY 握手失败 | UUID、公钥、short-id 与 SNI |
| TCP 可用，XHTTP 不可用 | 客户端内核支持、XHTTP 路径、Flow 是否留空 |
| 客户端仍显示旧配置 | 使用菜单 **8** 重新导出，再导入客户端 |

提交问题时，请附上操作系统、Xray 版本、客户端名称与版本，以及隐藏凭据后的相关日志。

[提交 Issue](https://github.com/passeway/Xray/issues) · [查看 CI](https://github.com/passeway/Xray/actions/workflows/check.yml)

---

本项目为独立的安装与管理工具，基于 [XTLS/Xray-core](https://github.com/XTLS/Xray-core)。官方安装项目见 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)，许可证见 [LICENSE](LICENSE)。
