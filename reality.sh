
#!/bin/bash

install_vless-reality() {
    curl -sS -o vless-reality.sh https://raw.githubusercontent.com/passeway/reality/main/vless-reality.sh &&
    chmod +x vless-reality.sh &&
    ./vless-reality.sh
}

uninstall_vless-reality() {
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}

echo "请选择操作："
echo "1. 安装 vless-reality"
echo "2. 卸载 vless-reality"
read -p "输入选项: " choice


case $choice in
    1)
        install_vless-reality
        ;;
    2)
        uninstall_vless-reality
        ;;
    *)
        echo "无效的选项"
        ;;
esac
