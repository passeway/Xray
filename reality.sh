#!/bin/bash

# 函数用于安装 vless-reality
install_vless_reality() {
    curl -sS -o vless-reality.sh https://raw.githubusercontent.com/passeway/reality/main/vless-reality.sh && chmod +x vless-reality.sh && ./vless-reality.sh
}

# 函数用于卸载 vless-reality
uninstall_vless_reality() {
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}

# 显示选项菜单
echo "请选择操作:"
echo "1. 安装 vless-reality"
echo "2. 卸载 vless-reality"
read -rp "请输入选项编号: " choice

# 根据用户选择执行相应操作
case "$choice" in
    1) install_vless_reality ;;
    2) uninstall_vless_reality ;;
    *) echo "无效的选项，请重新输入或退出" 
       read -rp "请输入选项编号或输入 'q' 退出: " new_choice
       case "$new_choice" in
            1) install_vless_reality ;;
            2) uninstall_vless_reality ;;
            q) echo "退出"; exit ;;
            *) echo "无效的选项，程序退出" ; exit ;;
       esac ;;
esac