## 终端预览

![preview](预览.png)

## 一键脚本
```
bash <(curl -fsSL xray-bay.vercel.app)
```

## 项目简介
- 输出客户端配置 url 方便快速设置

- 安装 Xray 配置 ss vless-reality 协议

- 自带 wireguard 出站解锁openai netflix disney

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
重载 Xray.service
```
sudo systemctl daemon-reload
```
修改 Xray.service
```
nano /etc/systemd/system/xray.service
```

检查 config.json 
```
/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
```
## Acme 证书

安装 certbot
```
sudo apt update
sudo apt install certbot
```
输入 domain
```
sudo certbot certonly --standalone -d example.com
```
复制 fullchain
```
cp /etc/letsencrypt/live/example.com/fullchain.pem /usr/local/etc/xray/fullchain.pem
cp /etc/letsencrypt/live/example.com/privkey.pem /usr/local/etc/xray/privkey.pem
```   
```
sudo chmod 755 /usr/local/etc/xray/fullchain.pem
sudo chmod 755 /usr/local/etc/xray/privkey.pem
```


## 项目地址：https://github.com/xtls/xray-core


