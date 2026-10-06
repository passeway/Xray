<div align="center">

# Xray

### 部署连接，简化运维。

面向 Linux 的 Xray 部署与服务管理工具。<br>
一次安装，提供 VLESS Vision、VLESS XHTTP 与 Shadowsocks 2022 三种连接方式。

[![Build](https://github.com/passeway/Xray/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Xray/actions/workflows/check.yml)
[![Xray Core](https://img.shields.io/badge/Xray-Core-18181b?style=flat-square)](https://github.com/XTLS/Xray-core)
![Platform](https://img.shields.io/badge/Linux-AMD64%20%7C%20ARM64-52525b?style=flat-square)
[![License](https://img.shields.io/github/license/passeway/Xray?style=flat-square&color=52525b)](LICENSE)

[快速开始](#快速开始) · [连接方式](#连接方式) · [管理服务](#管理服务) · [技术文档](#技术文档) · [反馈问题](https://github.com/passeway/Xray/issues)

</div>

---

**一个入口，完成部署与维护。**

官方内核下载与 SHA256 校验、连接凭据生成、客户端链接导出，以及 systemd / OpenRC 服务管理，均由同一个脚本完成。支持 AMD64 与 ARM64，自动使用服务器 IP 的国家/地区代码命名节点。

## 快速开始

以 **root** 身份，在已运行 systemd 或 OpenRC 的服务器上执行。

**Debian / Ubuntu / RHEL / Fedora 系**  
需要已安装 Bash 与 curl。

```bash
bash <(curl -fsSL https://xray-bay.vercel.app)
```

**Alpine / OpenRC**  
兼容 Alpine 默认的 ash 终端。

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://xray-bay.vercel.app)'
```

选择 **1** 安装，放行对应端口，然后将输出的 `vless://` 或 `ss://` 链接导入客户端。

> 两组 VLESS 各需放行一个 TCP 端口；SS2022 需同时放行其端口的 TCP 和 UDP。端口随机生成，以安装输出为准。

## 连接方式

三组节点默认一同安装，各使用独立端口。选择客户端支持的方式即可。

|  | VLESS Vision | VLESS XHTTP | Shadowsocks 2022 |
| :--- | :--- | :--- | :--- |
| 传输 | TCP + Vision | XHTTP · `auto` | TCP / UDP |
| 安全配置 | REALITY | REALITY | AES-128-GCM · 2022 |
| 导出格式 | `vless://` | `vless://` | `ss://` |
| 节点名称 | `HK-vless-tcp` | `HK-vless-xhttp` | `HK-ss2022` |

前缀根据公网 IP 自动识别，例如 `US`、`JP`、`HK`。地区查询失败时保留已有名称，新安装回退到公网 IP，无需输入确认。

<details>
<summary>连接参数与客户端要求</summary>

两组 VLESS 共用 UUID、REALITY 密钥对与 short-id，默认 SNI 为 `www.ua.edu`。客户端的地址、端口、UUID、公钥、short-id 和 SNI 应与所选入站一致。

- **Vision**：Flow 使用 `xtls-rprx-vision`。
- **XHTTP**：使用生成的随机路径与 `mode=auto`，Flow 留空。
- **SS2022**：加密方式为 `2022-blake3-aes-128-gcm`。独立生成 16 字节预共享密钥，以 Base64 保存；不使用 REALITY、SNI 或 Vision Flow。客户端须支持该加密方式。

XHTTP 当前面向直连 REALITY，沿用默认 XMUX、并发及缓冲参数。按[官方指南](https://github.com/XTLS/Xray-core/discussions/4113)，通常只需设置路径。CDN、反向代理或 QUIC/H3 需要单独设计配置，不能直接套用当前 REALITY 连接。

</details>

## 管理服务

重新运行安装命令即可进入管理菜单。

| 选项 | 操作 | 选项 | 操作 |
| :---: | :--- | :---: | :--- |
| **1** | 安装服务 | **6** | 检查状态 |
| **2** | 卸载服务与配置 | **7** | 查看实时日志 |
| **3** | 启动服务 | **8** | 导出客户端链接 |
| **4** | 停止服务 | **9** | 更新内核 |
| **5** | 重启服务 | **0** | 退出 |

安装自动配置开机自启。菜单 **3** 在服务已运行时会重启；菜单 **7** 可按 `Ctrl+C` 返回。卸载需要明确确认。

**同步客户端配置**  
修改服务端配置后，选择 **5** 重启，再选择 **8** 重新导出并导入客户端。查看已保存的链接：

```sh
cat /usr/local/etc/xray/config.txt
```

**更新内核**  
选择 **9**，新内核通过现有配置校验后才替换。更新保留端口、UUID、密钥和入站配置，不为旧安装自动增加协议。脚本不创建备份或自动回滚。

## 技术文档

<details>
<summary><strong>平台与依赖</strong> — 支持范围、运行环境</summary>

支持 Alpine（OpenRC）、Debian / Ubuntu 及 RHEL / Fedora 系（systemd），架构为 AMD64 / ARM64。

依赖通过 `apk`、`apt-get`、`dnf` 或 `yum` 按需安装，不执行整机软件升级。服务器必须已运行相应服务管理器；仅安装管理命令的普通容器不作为部署目标。

检测到已有程序、配置或服务时，脚本会阻止重复安装。

</details>

<details>
<summary><strong>服务与日志</strong> — systemd、OpenRC</summary>

**systemd**

```sh
systemctl start xray
systemctl stop xray
systemctl restart xray
systemctl status xray --no-pager
journalctl -u xray -n 50 --no-pager
journalctl -u xray -f
```

**OpenRC**

```sh
rc-service xray start
rc-service xray stop
rc-service xray restart
rc-service xray status
rc-update add xray default
tail -n 50 /var/log/xray/xray.log
tail -F /var/log/xray/xray.log
```

OpenRC 使用 `supervise-daemon` 守护进程并自动重启。文件日志需按使用量安排轮转，卸载时保留。

</details>

<details>
<summary><strong>文件与权限</strong> — 配置位置、服务身份</summary>

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/xray` | 内核 |
| `/usr/local/etc/xray/config.json` | 服务端配置 |
| `/usr/local/etc/xray/config.txt` | 客户端链接 |
| `/usr/local/etc/xray/client-meta.json` | 公网地址与名称前缀 |
| `/usr/local/share/xray` | 内核资源 |
| `/etc/systemd/system/xray.service` | systemd 服务单元 |
| `/etc/init.d/xray` | OpenRC 服务脚本 |
| `/var/log/xray/xray.log` | OpenRC 日志 |

新安装使用独立 `xray` 用户；更新沿用现有服务身份。配置目录权限为 `750`，服务端配置为 `640`，客户端链接和地址元数据为 `600`。

REALITY 私钥留在服务端，客户端使用公钥。国家/地区代码通过 `ipwho.is` 查询服务器公网 IP。

OpenRC 仅接受本脚本生成的服务定义。检测到服务脚本被修改或 `/etc/conf.d/xray` 非空时，会停止更新、重启和卸载，避免操作不匹配的服务。

</details>

<details>
<summary><strong>故障排查</strong> — 连通性、配置同步</summary>

| 现象 | 检查项 |
| :--- | :--- |
| 服务无法启动 | 服务状态、配置校验结果、日志 |
| 连接超时 | 监听端口、云安全组、服务器防火墙 |
| REALITY 握手失败 | UUID、公钥、short-id、SNI |
| XHTTP 无法连接 | 客户端支持、路径一致、Flow 留空 |
| SS2022 无法连接 | 加密方式、密钥、端口 |
| SS2022 仅 UDP 不通 | UDP 端口放行、客户端支持、网络连通性 |
| 客户端配置未更新 | 菜单 **8** 重新导出并导入 |

旧版 OpenRC 安装若提示“已有 Xray 管理操作正在运行”，先退出菜单并执行 `rc-service xray stop` 释放旧进程继承的锁，再运行最新版脚本。不要删除锁文件来绕过并发保护。

</details>

<details>
<summary><strong>验证范围</strong> — 自动测试与实机边界</summary>

CI 配置覆盖 Alpine、Debian、Ubuntu 与 Rocky Linux 容器，检查语法、失败处理、配置导出，以及官方内核下三组节点的 TCP 代理流量。当前运行结果见页面顶部的构建状态。

已有用户反馈 Alpine 实机节点连接与卸载可用。SS2022 原生 UDP、系统重启后的自启及 ARM64 实机行为仍需针对部署环境验证。

</details>

---

**项目与支持**  
基于 [XTLS/Xray-core](https://github.com/XTLS/Xray-core) 的独立安装与管理工具。

[报告问题](https://github.com/passeway/Xray/issues) · [构建记录](https://github.com/passeway/Xray/actions/workflows/check.yml) · [官方安装项目](https://github.com/XTLS/Xray-install) · [许可证](LICENSE)

反馈问题时请附上系统、内核和客户端版本，以及隐藏 UUID、密钥等凭据后的日志。
