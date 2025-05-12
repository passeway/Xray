#!/usr/bin/env python3

import os
import subprocess
import random
import json
import uuid
import base64
import requests

def check_root():
    if os.geteuid() != 0:
        print("Error: This script must be run as root!")
        exit(1)

def update_system():
    print("正在更新系统和安装依赖...")
    if os.path.exists("/usr/bin/apt-get"):
        subprocess.run(["apt-get", "update", "-y"])
        subprocess.run(["apt-get", "upgrade", "-y"])
        subprocess.run(["apt-get", "install", "-y", "gawk", "curl"])
    else:
        subprocess.run(["yum", "update", "-y"])
        subprocess.run(["yum", "upgrade", "-y"])
        subprocess.run(["yum", "install", "-y", "epel-release", "gawk", "curl"])

def get_random_ports():
    used_ports = subprocess.check_output("ss -ltn | awk '{print $4}' | awk -F ':' '{print $NF}'", shell=True).decode().split()
    used_ports = set(map(int, filter(str.isdigit, used_ports)))

    def generate():
        while True:
            p = random.randint(1024, 65000)
            if p not in used_ports:
                return p

    return generate(), generate()

def install_xray():
    subprocess.run(["bash", "-c", "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) @ install"])

def generate_keys():
    x25519 = subprocess.check_output(["/usr/local/bin/xray", "x25519"]).decode().splitlines()
    private_key = x25519[0].split()[2]
    public_key = x25519[1].split()[2]
    return private_key, public_key

def get_host_ip():
    try:
        ip = requests.get("http://www.cloudflare.com/cdn-cgi/trace").text
        for line in ip.splitlines():
            if line.startswith("ip="):
                return line.split('=')[1]
    except:
        pass

    try:
        ip = requests.get("http://www.cloudflare.com/cdn-cgi/trace", timeout=5).text
        for line in ip.splitlines():
            if line.startswith("ip="):
                return line.split('=')[1]
    except:
        pass
    return ""

def get_country(ip):
    try:
        return requests.get(f"http://ipinfo.io/{ip}/country").text.strip()
    except:
        return ""

def write_config(port1, port2, psk, uuid_str, private_key, public_key, path):
    config = {
        "log": {"loglevel": "warning"},
        "inbounds": [
            {
                "port": port1,
                "protocol": "shadowsocks",
                "settings": {
                    "method": "2022-blake3-aes-128-gcm",
                    "password": psk,
                    "network": "tcp,udp"
                }
            },
            {
                "port": port2,
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": uuid_str, "flow": ""}],
                    "decryption": "none",
                    "fallbacks": []
                },
                "streamSettings": {
                    "network": "xhttp",
                    "security": "reality",
                    "realitySettings": {
                        "show": False,
                        "dest": "www.tesla.com:443",
                        "xver": 0,
                        "serverNames": ["www.tesla.com"],
                        "privateKey": private_key,
                        "shortIds": ["123abc"],
                        "fingerprint": "chrome"
                    },
                    "xhttpSettings": {
                        "path": f"/{path}",
                        "host": "",
                        "headers": {},
                        "scMaxBufferedPosts": 30,
                        "scMaxEachPostBytes": "1000000",
                        "noSSEHeader": False,
                        "xPaddingBytes": "100-1000",
                        "mode": "auto"
                    }
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"]
                }
            }
        ],
        "outbounds": [{"protocol": "freedom", "tag": "direct"}]
    }

    os.makedirs("/usr/local/etc/xray", exist_ok=True)
    with open("/usr/local/etc/xray/config.json", "w") as f:
        json.dump(config, f, indent=2)

def save_client_config(host_ip, port1, port2, psk, uuid_str, public_key, path, country):
    psk_urlsafe = base64.urlsafe_b64encode(psk.encode()).decode().rstrip('=')
    with open("/usr/local/etc/xray/config.txt", "w") as f:
        f.write(f"ss://2022-blake3-aes-128-gcm:{psk_urlsafe}@{host_ip}:{port1}#{country}\n\n")
        f.write(f"{country} = ss, {host_ip}, {port1}, encrypt-method=2022-blake3-aes-128-gcm, password={psk}, udp-relay=true\n\n")
        vless = (
            f"vless://{uuid_str}@{host_ip}:{port2}?encryption=none&security=reality&sni=www.tesla.com&"
            f"fp=chrome&pbk={public_key}&sid=123abc&type=xhttp&path=%2F{path}&mode=auto#{country}\n"
        )
        f.write(vless)

def main():
    check_root()
    update_system()

    port1, port2 = get_random_ports()
    install_xray()

    path = os.urandom(6).hex()
    uuid_str = str(uuid.uuid4())
    psk = base64.b64encode(os.urandom(16)).decode().rstrip('=')

    private_key, public_key = generate_keys()
    write_config(port1, port2, psk, uuid_str, private_key, public_key, path)

    subprocess.run(["systemctl", "enable", "xray"])
    subprocess.run(["systemctl", "restart", "xray"])

    host_ip = get_host_ip()
    country = get_country(host_ip)
    save_client_config(host_ip, port1, port2, psk, uuid_str, public_key, path, country)

    print("Xray 安装完成\n")
    with open("/usr/local/etc/xray/config.txt") as f:
        print(f.read())

if __name__ == "__main__":
    main()
