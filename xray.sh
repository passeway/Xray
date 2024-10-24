#!/bin/bash

# 确保脚本以root身份运行
if [[ ${EUID} -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 生成uuid
v2uuid=$(cat /proc/sys/kernel/random/uuid)

# 生成base64
psk=$(openssl rand -base64 16)

# 下载并执行脚本，将输出导入当前shell环境
eval "$(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/wireguard.sh)"

# 提取变量
WARP_IPV4=$(echo "$WARP_IPV4")
WARP_IPV6=$(echo "$WARP_IPV6")
WARP_private=$(echo "$WARP_private")
WARP_Reserved=$(echo "$WARP_Reserved")

# 获取随机端口
getPorts() {
    local port1 port2
    port1=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    while nc -z localhost "${port1}"; do
        port1=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    done

    port2=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    while nc -z localhost "${port2}" || [ "${port2}" -eq "${port1}" ]; do
        port2=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    done

    echo "${port1} ${port2}"
}

# 获取两个随机端口
PORTS=($(getPorts))
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

    # 重新配置Xray
    cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "debug"
  },
  "dns": {
    "servers": [
      "https://1.1.1.1/dns-query",
      "https://8.8.8.8/dns-query"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "domain": [
          "geosite:openai"
        ],
        "outboundTag": "warp"
      },
      {
        "domain": [
          "geosite:netflix"
        ],
        "outboundTag": "warp"
      },
      {
        "domain": [
          "geosite:disney"
        ],
        "outboundTag": "warp"
      }
    ]
  },
  "inbounds": [
    {
      "port": "${PORT1}",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${v2uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "1.1.1.1:443",
          "serverNames": [
            "www.tesla.com"
          ],
          "privateKey": "${rePrivateKey}",
          "shortIds": [
            "",
            "123abc"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    },
    {
      "port": ${PORT2},
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "${psk}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "tag": "direct"
    },
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${WARP_private}",
        "address": [
          "172.16.0.2/32",
          "${WARP_IPV6}/128"
        ],
        "peers": [
          {
            "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "${WARP_IPV4}:2408"
          }
        ],
        "reserved": [${WARP_Reserved}],
        "mtu": 1280
      },
      "tag": "warp"
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
    # 删除服务脚本
    rm -f tcp-wss.sh install-release.sh
    # 生成客户端配置信息
    cat << EOF > /usr/local/etc/xray/config.txt
ss://2022-blake3-chacha20-poly1305:${psk}@${HOST_IP}:${PORT2}#${IP_COUNTRY}

${IP_COUNTRY} = ss, ${HOST_IP}, ${PORT2}, encrypt-method=2022-blake3-aes-128-gcm, password=${psk}, udp-relay=true

vless://${v2uuid}@${HOST_IP}:${PORT1}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.tesla.com&fp=chrome&pbk=${rePublicKey}&sid=123abc&type=tcp&headerType=none#${IP_COUNTRY}
EOF
    
    echo "Xray 安装成功"
    cat /usr/local/etc/xray/config.txt
    
}

install_xray
reconfig
