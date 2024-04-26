#!/bin/bash

# 确保脚本以 root 身份运行
if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# 安装 qrencode
if ! command -v qrencode &> /dev/null; then
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y
        apt-get install -y qrencode
    else
        yum update -y
        yum install -y qrencode
    fi
fi

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 生成 UUID
v2uuid=$(cat /proc/sys/kernel/random/uuid)

# 获取随机端口
getPort() {
    local port
    port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    while nc -z localhost "$port"; do
        port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    done
    echo "$port"
}

PORT=$(getPort)

# 获取 IP 地址
getIP() {
    local serverIP
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "=" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "=" '{print $2}')
    fi
    echo "${serverIP}"
}

install_xray() {
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y gawk curl
    else
        yum update -y && yum upgrade -y
        yum install -y epel-release
        yum install -y gawk curl
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

reconfig() {
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | head -1 | awk '{print $3}')
    rePublicKey=$(echo "${reX25519Key}" | tail -n 1 | awk '{print $3}')

    # 重新配置 Xray
    cat >/usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$v2uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "1.1.1.1:443",
                    "xver": 0,
                    "serverNames": [
                        "www.apple.com"
                    ],
                    "privateKey": "$rePrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "shortIds": [
                        "88",
                        "123abc"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]    
}
EOF

    # 启动 Xray 服务
    systemctl enable xray.service && systemctl restart xray.service

    # 获取国家信息
    IP_COUNTRY=$(curl -s http://ipinfo.io/$(getIP)/country)

    # 删除临时文件
    rm -f tcp-wss.sh install-release.sh reality.sh vless-reality.sh

    # 生成 VLESS 链接
    vless_link="vless://${v2uuid}@$(getIP):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#$IP_COUNTRY"

    # 输出 VLESS 链接
    echo "VLESS 链接: ${vless_link}"

    # 生成二维码并显示在终端
    qrencode -t ANSI256 "${vless_link}"
}

install_xray
reconfig
