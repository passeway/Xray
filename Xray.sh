#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 函数用于安装 Xray
install_vless_reality() {
   bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Xray/refs/heads/main/xray.sh)
}

# 函数用于更新 Xray
upgrade_vless_reality() {
    bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
    systemctl restart xray
}

# 函数用于卸载 Xray
uninstall_vless_reality() {
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}

# 函数用于检查 Xray 安装状态
check_vless_reality_status() {
    if command -v xray &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 函数用于检查 Xray 运行状态
check_vless_reality_running() {
    if systemctl is-active --quiet xray; then
        return 0
    else
        return 1
    fi
}

# 显示选项菜单
show_menu() {
    clear
    echo -e "${GREEN}=== Xray 管理工具 ===${RESET}"
    check_vless_reality_status
    xray_installed=$?
    check_vless_reality_running
    xray_running=$?

    echo -e "${GREEN}安装状态: $(if [ ${xray_installed} -eq 0 ]; then echo "${GREEN}已安装${RESET}"; else echo "${RED}未安装${RESET}"; fi)${RESET}"
    echo -e "${GREEN}运行状态: $(if [ ${xray_running} -eq 0 ]; then echo "${GREEN}已运行${RESET}"; else echo "${RED}未运行${RESET}"; fi)${RESET}"
    echo ""
    echo "1. 安装 Xray 服务"
    echo "2. 卸载 Xray 服务"
    echo "3. 启动 Xray 服务"
    echo "4. 停止 Xray 服务"
    echo "5. 重启 Xray 服务"
    echo "6. 检查 Xray 状态"
    echo "7. 查看 Xray 日志"
    echo "8. 查看 Xray 配置"
    echo "9. 更新 Xray 内核"
    echo "0. 退出"
    echo -e "${GREEN}=====================${RESET}"
    read -p "请输入选项编号: " choice
    echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
while true; do
    show_menu
    case "$choice" in
        1) install_vless_reality ;;
        2) uninstall_vless_reality ;;
        3) sudo systemctl start xray ;;
        4) sudo systemctl stop xray ;;
        5) sudo systemctl restart xray ;;
        6) sudo systemctl status xray ;;
        7) sudo journalctl -u xray -f ;;
        8) cat /usr/local/etc/xray/config.txt ;;
        9) upgrade_vless_reality ;;
        0)
            echo -e "${GREEN}已退出 Xray 管理工具${RESET}"
            exit 0
            ;;
        *) echo -e "${RED}无效的选项${RESET}" ;;
    esac
    read -p "按 Enter 键继续..."
done
