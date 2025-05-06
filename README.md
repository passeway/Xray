## 终端预览

![preview](image.png)

## 一键脚本
```
bash <(curl -fsSL xray-bay.vercel.app)
```

## Xray指令
启动 Xray 服务
```
sudo systemctl start xray
```
停止 Xray 服务
```
sudo systemctl stop xray
```
重启 Xray 服务
```
sudo systemctl restart xray
```
检查 Xray 状态
```
sudo systemctl status xray
```

## 协议优势

### 1️⃣ Shadowsocks 2022

| 特性 | 优势 |
|------|------|
| **现代加密算法** | 采用 AEAD 加密（BLAKE3 + AES-GCM），抗主动探测能力强、安全性更高 |
| **抗重放攻击** | 一次性密钥派生机制，防止流量被复用 |
| **更快的加密性能** | BLAKE3 哈希算法速度快，配合 AES-NI 加速，性能优异 |
| **更难被识别** | 数据包隐蔽性强，抗 DPI 识别能力出色 |
| **UDP / TCP 支持** | 支持 UDP 转发，适合游戏加速等场景 |

> **总结**：Shadowsocks 2022（SS2022）是 Shadowsocks 协议的下一代升级版，专注于更强的安全性与性能。

---

### 2️⃣ VLESS + REALITY + XHTTP

| 特性 | 优势 |
|------|------|
| **REALITY 加密** | 利用真实站点证书与私钥，伪装 HTTPS 连接，极难被识别与封锁 |
| **无需伪造证书** | 使用真实证书，无自签证书风险 |
| **XHTTP 传输** | 流量形态接近真实网页访问，混淆性强 |
| **支持多路径与短 ID** | 连接细节随机化，流量不可预测性强 |
| **低延迟高性能** | 比传统 WebSocket 更低延迟、更稳定 |
| **抗主动探测强** | 连接行为与真实 HTTPS 无异，防探测能力一流 |

> **总结**：VLESS 是 Xray 项目推出的轻量级无加密认证协议，结合 REALITY 传输层加密与 XHTTP 伪装，隐蔽性极强，专为复杂网络环境设计。



## 项目地址：https://github.com/xtls/xray-core


