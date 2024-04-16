#!/bin/bash

# 显示选项
echo "选项1：安装 reality"
echo "选项2：卸载 reality"
read -p "请选择操作（输入选项编号）：" choice

# 执行相应操作
case $choice in
    1)
        install_reality
        ;;
    2)
        uninstall_reality
        ;;
    *)
        echo "错误：请输入有效选项编号！"
        exit 1
        ;;
esac

# 定义安装函数
install_reality() {
    if [[ $EUID -ne 0 ]]; then
        clear
        echo "错误：此脚本必须以root权限运行！" 1>&2
        exit 1
    fi
    
    # 设置服务器时区为上海
    timedatectl set-timezone Asia/Shanghai

    # 生成一个随机的UUID作为服务器标识
    v2uuid=$(cat /proc/sys/kernel/random/uuid)

    # 获取一个未被占用的随机端口号
    PORT=$(getPort)

    # 获取服务器IP地址
    IP=$(getIP)

    # 安装Xray及所需的软件包
    install_xray

    # 配置Xray服务器
    reconfig

    # 显示客户端配置信息
    client_re
}

# 定义卸载函数
uninstall_reality() {
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}

# 获取一个未被占用的随机端口号
getPort() {
    local port
    port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    while nc -z localhost "$port"; do
        port=$(shuf -i 1024-49151 -n 1 2>/dev/null)
    done
    echo "$port"
}

# 获取服务器IP地址
getIP() {
    local serverIP
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}

# 安装Xray及所需的软件包
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

# 配置Xray服务器
reconfig() {
    # 生成X25519密钥
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | head -1 | awk '{print $3}')
    rePublicKey=$(echo "${reX25519Key}" | tail -n 1 | awk '{print $3}')

    # 写入Xray配置文件
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
                    "dest": "www.amazon.com:443",
                    "xver": 0,
                    "serverNames": [
                        "www.amazon.com",
                        "addons.mozilla.org",
                        "www.un.org",
                        "www.tesla.com"
                    ],
                    "privateKey": "$rePrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
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

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

    # 启用并重启Xray服务
    systemctl enable xray.service && systemctl restart xray.service
    rm -f tcp-wss.sh install-release.sh reality.sh

    # 写入客户端配置文件
    cat >/usr/local/etc/xray/reclient.json <<EOF
{
===========配置参数=============
代理模式：vless
地址：$(getIP)
端口：${PORT}
UUID：${v2uuid}
流控：xtls-rprx-vision
传输协议：tcp
Public key：${rePublicKey}
底层传输：reality
SNI: www.amazon.com
shortIds: 88
====================================
vless://${v2uuid}@$(getIP):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.amazon.com&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#$IP_COUNTRY

}
EOF

    clear
}

# 显示客户端配置信息
client_re() {
    echo
    echo "安装已完成"
    echo
    echo "===========reality配置参数============"
    echo "代理模式：vless"
    echo "地址：$(getIP)"
    echo "端口：${PORT}"
    echo "UUID：${v2uuid}"
    echo "流控：xtls-rprx-vision"
    echo "传输协议：tcp"
    echo "Public key：${rePublicKey}"
    echo "底层传输：reality"
    echo "SNI: www.amazon.com"
    echo "shortIds: 88"
    echo "===================================="
    echo "vless://${v2uuid}@$(getIP):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.amazon.com&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#$IP_COUNTRY"
    echo
}