#!/bin/bash

install_vless_reality() {
    curl -sS -o vless-reality.sh https://raw.githubusercontent.com/passeway/reality/main/vless-reality.sh &&
    chmod +x vless-reality.sh &&
    ./vless-reality.sh
}

uninstall_vless_reality() {
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}

echo "请选择操作："
echo "1. 安装vless-reality"
echo "2. 卸载vless-reality"
read -p "输入选项: " choice


case $choice in
    1)
        install_vless_reality
        ;;
    2)
        uninstall_vless_reality
        ;;
    *)
        echo "错误: 无效的选项，请输入 '1' 或 '2'"
        ;;
esac
