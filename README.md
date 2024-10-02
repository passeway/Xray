## 终端预览

![preview](预览.png)

## 一键脚本
```
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Xray/main/Xray.sh)
```
## 详细说明

- 安装Xray并配置 Reality传输协议

- 输出客户端配置 URL，方便快速设置

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
申请 Acme 证书
```
sudo apt update
sudo apt install certbot
```
```
sudo certbot certonly --standalone -d example.com
```
```
cp /etc/letsencrypt/live/example.com/fullchain.pem /usr/local/etc/xray/fullchain.pem
cp /etc/letsencrypt/live/example.com/privkey.pem /usr/local/etc/xray/privkey.pem
```
重新加载 systemd 配置
```
sudo systemctl daemon-reload
```
## 项目地址：https://github.com/xtls/xray-core


