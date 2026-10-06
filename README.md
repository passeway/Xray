<div align="center">

# Xray

### 两种传输，统一管理。

基于 Xray-core 的 VLESS + REALITY 安装与服务管理脚本。

**TCP · Vision · XHTTP · REALITY**

[![Core](https://img.shields.io/badge/Core-Xray-2563eb?style=flat-square)](https://github.com/XTLS/Xray-core)
![Service](https://img.shields.io/badge/Linux-systemd-475569?style=flat-square)
[![License](https://img.shields.io/github/license/passeway/Xray?style=flat-square)](LICENSE)

[快速开始](#快速开始) · [协议配置](#协议配置) · [日常管理](#日常管理) · [客户端连接](#客户端连接) · [问题反馈](https://github.com/passeway/Xray/issues)

</div>

---

通过一个交互菜单，完成 Xray 的安装、启停、重启、内核更新和日志查看。安装时生成 TCP 与 XHTTP 两组 VLESS + REALITY 入站，并输出对应的客户端分享链接。

| 部署 | 管理 | 连接 |
| :--- | :--- | :--- |
| 调用官方 Xray 安装脚本 | systemd 服务管理 | 两组 VLESS 分享链接 |
| 随机端口、UUID 与 REALITY 密钥 | 状态查询与实时日志 | TCP + Vision / XHTTP |
| 随机 short-id 与 XHTTP 路径 | 菜单查看已保存的连接信息 | 两组入站使用不同端口 |

## 快速开始

以 **root** 身份，在已安装 `bash`、`curl` 的终端执行：

```bash
bash <(curl -fsSL xray-bay.vercel.app)
```

**运行脚本 → 选择 `1` 安装 → 放行两个 TCP 端口 → 导入对应的分享链接。**

### 运行环境

| 要求 | 说明 |
| :--- | :--- |
| 服务管理 | 使用 systemd 的 Linux 系统 |
| 包管理器 | 当前安装逻辑包含 `apt-get` 与 `yum` 分支 |
| 执行权限 | root；菜单中的服务操作还会调用 `sudo` |
| 客户端 | 支持所选传输方式及 REALITY 的客户端与内核 |

当前脚本未适配 Alpine / OpenRC。

> [!NOTE]
> 安装过程会执行系统软件包更新，并写入 `/usr/local/etc/xray/config.json`。已有 Xray 配置时，请先确认安装操作符合你的需求。

> [!IMPORTANT]
> 云安全组与服务器防火墙需要放行实际生成的两个 TCP 端口。脚本会在安装后输出端口和客户端链接。

## 协议配置

| 项目 | VLESS + TCP + REALITY | VLESS + XHTTP + REALITY |
| :--- | :--- | :--- |
| 传输方式 | TCP | XHTTP |
| Flow | `xtls-rprx-vision` | 空，不设置 Vision |
| 端口 | 随机生成 | 随机生成，与 TCP 入站不同 |
| 路径 | 无需设置 | 随机路径，以生成的链接为准 |
| REALITY SNI | `www.ua.edu` | `www.ua.edu` |
| 客户端导出 | `vless://` 分享链接 | `vless://` 分享链接，`mode=auto` |

两组入站共用本次生成的 UUID、REALITY 密钥对及 short-id。客户端参数需与相应入站保持一致。

## 日常管理

重新运行安装命令即可打开管理菜单：

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 Xray 服务 |
| `2` | 卸载 Xray 服务 |
| `3` | 启动 Xray 服务 |
| `4` | 停止 Xray 服务 |
| `5` | 重启 Xray 服务 |
| `6` | 检查 Xray 状态 |
| `7` | 查看实时日志 |
| `8` | 查看已保存的客户端分享链接 |
| `9` | 更新 Xray 内核 |
| `0` | 退出 |

### 常用命令

```bash
# 启动 / 停止 / 重启
systemctl start xray
systemctl stop xray
systemctl restart xray

# 查看状态与近期日志
systemctl status xray --no-pager
journalctl -u xray -n 50 --no-pager
```

## 客户端连接

安装完成后，复制输出中的 `vless://` 链接，在支持对应协议的客户端中导入。两条链接分别对应 TCP + Vision 和 XHTTP。

也可以选择菜单 **8**，或执行：

```bash
cat /usr/local/etc/xray/config.txt
```

> [!NOTE]
> 菜单 **8** 只显示已保存的连接信息，不会重新生成链接。手动修改服务端配置后，需要同步调整客户端参数，并重启服务使改动生效。

### 参数核对

| 参数 | 需要保持一致的内容 |
| :--- | :--- |
| 地址与端口 | 服务器公网地址、所选入站的监听端口 |
| UUID | 对应入站的用户 ID |
| REALITY | 公钥、short-id、SNI |
| TCP + Vision | TCP 传输，`flow=xtls-rprx-vision` |
| XHTTP | XHTTP 传输、生成的路径，Flow 留空 |

服务端配置位于 `/usr/local/etc/xray/config.json`。REALITY 私钥仅用于服务端，客户端使用对应公钥。

## 排查问题

| 现象 | 优先检查 |
| :--- | :--- |
| 服务未启动 | `systemctl status xray` 与服务日志 |
| 客户端连接超时 | 实际监听端口、云安全组与服务器防火墙 |
| REALITY 连接失败 | UUID、公钥、short-id、SNI 是否匹配 |
| TCP 能用，XHTTP 不能用 | 客户端内核是否支持 XHTTP，路径与 Flow 是否正确 |
| 修改后仍显示旧链接 | 菜单 `8` 读取的是保存的文本，需要同步更新客户端参数 |

<details>
<summary><strong>查看实时日志</strong></summary>

```bash
journalctl -u xray -f
```

在独立终端运行上述命令，再发起客户端连接，观察新产生的错误信息；按 `Ctrl+C` 结束查看。

</details>

反馈问题时请提供系统、Xray 版本、客户端名称与版本以及相关日志，并隐藏 UUID、私钥和其他凭据。

---

<div align="center">

基于 [XTLS/Xray-core](https://github.com/XTLS/Xray-core) · 本仓库为独立安装与管理脚本项目

[官方安装项目](https://github.com/XTLS/Xray-install) · [提交问题](https://github.com/passeway/Xray/issues)

</div>
