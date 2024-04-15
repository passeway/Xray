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