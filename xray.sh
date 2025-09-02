#!/bin/bash


# 检查root权限并更新系统
root() {
    # 检查root权限
    if [[ ${EUID} -ne 0 ]]; then
        echo "Error: This script must be run as root!" 1>&2
        exit 1
    fi
    
    # 更新系统和安装基础依赖
    echo "正在更新系统和安装依赖"
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y gawk curl
    else
        yum update -y && yum upgrade -y
        yum install -y epel-release gawk curl
    fi
}

# 获取随机端口
port() {    
    local port1 port2    
    port1=$(shuf -i 1024-65000 -n 1)
    while ss -ltn | grep -q ":$port1"; do
        port1=$(shuf -i 1024-65000 -n 1)
    done    
    port2=$(shuf -i 1024-65000 -n 1)
    while ss -ltn | grep -q ":$port2" || [ "$port2" -eq "$port1" ]; do
        port2=$(shuf -i 1024-65000 -n 1)
    done
    
    PORT1=$port1
    PORT2=$port2    
}

# 配置和启动Xray
xray() {
    # 安装Xray内核
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    # 生成所需参数
    path=$(openssl rand -hex 8)
    shid=$(openssl rand -hex 8)
    uuid=$(/usr/local/bin/xray uuid)
    X25519Key=$(/usr/local/bin/xray x25519)
    PrivateKey=$(echo "$X25519Key" | grep -i '^PrivateKey:' | awk '{print $2}')
    PublicKey=$(echo "$X25519Key" | grep -E '^(PublicKey|Password):' | awk '{print $2}')

    # 配置config.json
    cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": "${PORT1}",
      "tag": "vless-tcp",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "target": "www.ua.edu:443",
          "serverNames": [
            "www.ua.edu"
          ],
          "privateKey": "${PrivateKey}",
          "shortIds": [
            "${shid}"
          ]
        }
      }
    },
    {
      "port": "${PORT2}",
      "tag": "vless-xhttp",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
            "path": "/${path}"
        },   
        "security": "reality",
        "realitySettings": {
          "target": "www.ua.edu:443",
          "serverNames": [
            "www.ua.edu"
          ],
          "privateKey": "${PrivateKey}",
          "shortIds": [
            "${shid}"
          ]
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
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

    # 启动Xray服务
    systemctl enable xray.service && systemctl restart xray.service
    if ! systemctl is-active --quiet xray.service; then
      echo "Xray 启动失败"
      exit 1
    fi
    
    # 获取IP并生成客户端配置
    HOST_IP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${HOST_IP}" ]]; then
        HOST_IP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    
    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    
    # 生成并保存客户端配置
    cat << EOF > /usr/local/etc/xray/config.txt

vless-tcp-reality
vless://${uuid}@${HOST_IP}:${PORT1}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.ua.edu&fp=chrome&pbk=${PublicKey}&sid=${shid}&type=tcp&headerType=none#${IP_COUNTRY}

vless-xhttp-reality
vless://${uuid}@${HOST_IP}:${PORT2}?encryption=none&security=reality&sni=www.ua.edu&fp=chrome&pbk=${PublicKey}&sid=${shid}&type=xhttp&path=%2F${path}&mode=auto#${IP_COUNTRY}
EOF

    echo "Xray 安装完成"
    cat /usr/local/etc/xray/config.txt
}

# 主函数
main() {
    root
    port
    xray
}

# 执行脚本
main
