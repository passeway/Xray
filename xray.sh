#!/bin/bash

# 确保脚本以root身份运行
if [[ ${EUID} -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 生成path && uuid && pak
path=$(openssl rand -hex 6)
uuid=$(cat /proc/sys/kernel/random/uuid)
psk=$(openssl rand -base64 16)
psk_urlsafe=$(echo -n "$psk" | tr '+/' '-_')


# 检查端口是否被占用
isPortUsed() {
    local port=$1
    ss -ltn | grep -q ":$port"
}

# 获取随机两个端口
Ports() {
    local port1 port2
    port1=$(shuf -i 1024-49151 -n 1)
    while isPortUsed "$port1"; do
        port1=$(shuf -i 1024-49151 -n 1)
    done

    port2=$(shuf -i 1024-49151 -n 1)
    while isPortUsed "$port2" || [ "$port2" -eq "$port1" ]; do
        port2=$(shuf -i 1024-49151 -n 1)
    done

    echo "$port1 $port2"
}


# 获取随机两个端口
PORTS=($(Ports))
PORT1=${PORTS[0]}
PORT2=${PORTS[1]}



# 获取IP地址
getIP() {
    local serverIP
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}


# 安装 xray
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
    X25519Key=$(/usr/local/bin/xray x25519)
    PrivateKey=$(echo "${X25519Key}" | head -1 | awk '{print $3}')
    PublicKey=$(echo "${X25519Key}" | tail -n 1 | awk '{print $3}')

    # 重新配置config.json
    cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT1},
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "${psk}",
        "network": "tcp,udp"
      }
    },
    {
      "port": ${PORT2},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": ""
          }
        ],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.tesla.com:443",
          "xver": 0,
          "serverNames": [
            "www.tesla.com"
          ],
          "privateKey": "${PrivateKey}",
          "publicKey": "${PublicKey}",
          "shortIds": [
            "123abc"
          ],
          "fingerprint": "chrome"
        },
        "xhttpSettings": {
          "path": "${path}",
          "host": "",
          "headers": {},
          "scMaxBufferedPosts": 30,
          "scMaxEachPostBytes": "1000000",
          "noSSEHeader": false,
          "xPaddingBytes": "100-1000",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
            "http", 
            "tls", 
            "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    # 启动Xray服务
    systemctl enable xray.service && systemctl restart xray.service
    
    # 获取本机IP地址
    HOST_IP=$(getIP)
    
    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    
    
    # 生成客户端配置信息
    cat << EOF > /usr/local/etc/xray/config.txt
ss://2022-blake3-aes-128-gcm:${psk_urlsafe}@${HOST_IP}:${PORT1}#${IP_COUNTRY}

${IP_COUNTRY} = ss, ${HOST_IP}, ${PORT1}, encrypt-method=2022-blake3-aes-128-gcm, password=${psk}, udp-relay=true

vless://${uuid}@${HOST_IP}:${PORT2}?encryption=none&security=reality&sni=www.tesla.com&fp=chrome&pbk=${PublicKey}&sid=123abc&type=xhttp&path=%2F${path}&mode=auto#${IP_COUNTRY}
EOF
    
    echo "Xray 安装成功"
    cat /usr/local/etc/xray/config.txt
    
}

install_xray
reconfig
