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

## [VLESS + XHTTP + REALITY](https://github.com/XTLS/Xray-core/discussions/4113) 

| 核心特性 | 详细优势说明 |
|:-------:|:------------|
|  **REALITY 技术** | 借用真实网站的 TLS 指纹特征，实现"完美伪装"，连接与访问真实网站无差别 |
|  **零信任验证** | 无需部署自签证书，规避 SSL 证书异常带来的风险，同时保持 TLS 加密强度 |
|  **XHTTP 流量** | 流量包特征与标准 HTTP/HTTPS 访问完全一致，通过流量形态分析也无法区分 |
|  **低延迟传输** | 比传统 WebSocket 协议减少 30-50% 延迟，视频会议、在线游戏体验更流畅 |
|  **主动探测免疫** | 对主动探测请求表现与真实站点一致，即使面对深度包检测也能保持稳定连接 |

> **核心优势**：VLESS + XHTTP + REALITY 组合代表了当前最先进的协议伪装技术，通过 REALITY 技术策略实现近乎完美的伪装效果，特别适合严苛网络环境和对隐蔽性有极高要求的场景。



## 项目地址：https://github.com/xtls/xray-core


