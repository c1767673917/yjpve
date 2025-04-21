#!/bin/bash

# 颜色设置
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 确认是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN}必须使用root用户运行此脚本！\n" && exit 1

# 检查系统
if [ -f /etc/redhat-release ]; then
    echo -e "${RED}错误：${PLAIN}此脚本仅支持Debian/Ubuntu系统！\n" && exit 1
fi

# 确认是否已安装PVE
if ! command -v qm &> /dev/null; then
    echo -e "${RED}错误：${PLAIN}未检测到PVE环境，请先安装PVE！\n"
    echo -e "${YELLOW}是否需要安装PVE？(y/n)${PLAIN}"
    read -r install_pve
    if [[ "$install_pve" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在安装PVE...${PLAIN}"
        curl -L https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/install_pve.sh -o install_pve.sh && chmod +x install_pve.sh && bash install_pve.sh
        exit 0
    else
        exit 1
    fi
fi

# 功能：检查是否为国内网络
check_cn() {
    curl -sm 3 https://www.baidu.com > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "cn"
    else
        echo "global"
    fi
}

# 下载脚本函数
download_script() {
    local script_name=$1
    local location=$(check_cn)
    
    if [ "$location" = "cn" ]; then
        echo -e "${YELLOW}检测到国内网络，使用国内CDN下载${PLAIN}"
        curl -L "https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/${script_name}" -o "${script_name}" && chmod +x "${script_name}"
    else
        echo -e "${YELLOW}使用国际网络下载${PLAIN}"
        curl -L "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/${script_name}" -o "${script_name}" && chmod +x "${script_name}"
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载脚本失败，请检查网络连接！${PLAIN}"
        return 1
    fi
    return 0
}

# 功能：单独创建KVM虚拟机
create_single_vm() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}单独创建KVM虚拟机${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    if [ ! -f "buildvm.sh" ]; then
        echo -e "${YELLOW}下载创建脚本...${PLAIN}"
        download_script "buildvm.sh" || return 1
    fi
    
    echo -e "${YELLOW}请输入以下参数：${PLAIN}"
    
    read -p "VMID (100-256): " vmid
    if [ -z "$vmid" ] || [ "$vmid" -lt 100 ] || [ "$vmid" -gt 256 ]; then
        echo -e "${RED}错误：VMID必须在100-256范围内！${PLAIN}"
        return 1
    fi
    
    read -p "用户名 (不能为纯数字，最好是纯英文): " username
    if [ -z "$username" ] || [[ "$username" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：用户名不能为空或纯数字！${PLAIN}"
        return 1
    fi
    
    read -p "密码 (建议英文与数字混合，以英文开头): " password
    if [ -z "$password" ]; then
        echo -e "${RED}错误：密码不能为空！${PLAIN}"
        return 1
    fi
    
    read -p "CPU核数: " cpu
    if [ -z "$cpu" ] || [ "$cpu" -lt 1 ]; then
        echo -e "${YELLOW}未指定或无效值，使用默认值: 1${PLAIN}"
        cpu=1
    fi
    
    read -p "内存大小(MB): " memory
    if [ -z "$memory" ] || [ "$memory" -lt 128 ]; then
        echo -e "${YELLOW}未指定或无效值，使用默认值: 512${PLAIN}"
        memory=512
    fi
    
    read -p "硬盘大小(GB): " disk
    if [ -z "$disk" ] || [ "$disk" -lt 5 ]; then
        echo -e "${YELLOW}未指定或无效值，使用默认值: 10${PLAIN}"
        disk=10
    fi
    
    read -p "SSH端口: " ssh_port
    if [ -z "$ssh_port" ]; then
        ssh_port=$((40000 + vmid))
        echo -e "${YELLOW}未指定，使用默认值: ${ssh_port}${PLAIN}"
    fi
    
    read -p "80端口: " http_port
    if [ -z "$http_port" ]; then
        http_port=$((41000 + vmid))
        echo -e "${YELLOW}未指定，使用默认值: ${http_port}${PLAIN}"
    fi
    
    read -p "443端口: " https_port
    if [ -z "$https_port" ]; then
        https_port=$((42000 + vmid))
        echo -e "${YELLOW}未指定，使用默认值: ${https_port}${PLAIN}"
    fi
    
    read -p "是否开启全端口映射？(1-65535) (Y/N，默认N): " full_port
    if [[ "$full_port" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已启用全端口映射模式${PLAIN}"
        # 保留一些宿主机系统必要端口
        port_start=1025
        port_end=65535
        echo -e "${YELLOW}端口映射范围: ${port_start}-${port_end}${PLAIN}"
    else
        read -p "内外网映射端口起始 (例如50000): " port_start
        if [ -z "$port_start" ]; then
            port_start=50000
            echo -e "${YELLOW}未指定，使用默认值: ${port_start}${PLAIN}"
        fi
        
        read -p "内外网映射端口结束 (例如50025): " port_end
        if [ -z "$port_end" ]; then
            port_end=$((port_start + 25))
            echo -e "${YELLOW}未指定，使用默认值: ${port_end}${PLAIN}"
        fi
    fi
    
    read -p "系统 (例如debian11): " os
    if [ -z "$os" ]; then
        os="debian11"
        echo -e "${YELLOW}未指定，使用默认值: ${os}${PLAIN}"
    fi
    
    read -p "存储盘 (默认local): " storage
    if [ -z "$storage" ]; then
        storage="local"
        echo -e "${YELLOW}未指定，使用默认值: ${storage}${PLAIN}"
    fi
    
    read -p "是否绑定独立IPV6 (Y/N，默认N): " ipv6
    if [ -z "$ipv6" ]; then
        ipv6="N"
    elif [[ "$ipv6" =~ ^[Yy]$ ]]; then
        ipv6="Y"
    else
        ipv6="N"
    fi
    
    echo -e "${GREEN}创建虚拟机中，请稍候...${PLAIN}"
    
    ./buildvm.sh "$vmid" "$username" "$password" "$cpu" "$memory" "$disk" "$ssh_port" "$http_port" "$https_port" "$port_start" "$port_end" "$os" "$storage" "$ipv6"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}虚拟机创建成功！VMID: ${vmid}${PLAIN}"
        echo -e "${YELLOW}可以执行 'cat vm${vmid}' 查看详细信息${PLAIN}"
        
        # 全端口映射设置说明
        if [[ "$full_port" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}================${PLAIN}"
            echo -e "${GREEN}全端口映射已开启${PLAIN}"
            echo -e "${GREEN}================${PLAIN}"
            echo -e "${YELLOW}此虚拟机现在拥有几乎所有端口的映射，除了系统保留的1-1024端口。${PLAIN}"
            echo -e "${YELLOW}您可以在虚拟机内使用任意端口，无需额外配置端口映射。${PLAIN}"
            echo -e "${YELLOW}SSH端口: ${ssh_port}${PLAIN}"
            echo -e "${YELLOW}HTTP端口: ${http_port}${PLAIN}"
            echo -e "${YELLOW}HTTPS端口: ${https_port}${PLAIN}"
            echo -e "${YELLOW}其他所有端口(${port_start}-${port_end})都已映射到宿主机相同端口号。${PLAIN}"
        fi
    else
        echo -e "${RED}虚拟机创建失败！${PLAIN}"
    fi
}

# 功能：批量创建KVM虚拟机
create_batch_vm() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}批量创建KVM虚拟机${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    if [ ! -f "create_vm.sh" ]; then
        echo -e "${YELLOW}下载批量创建脚本...${PLAIN}"
        download_script "create_vm.sh" || return 1
    fi
    
    echo -e "${YELLOW}执行批量创建脚本，请按照提示操作...${PLAIN}"
    echo -e "${YELLOW}注意：建议使用screen挂起执行，避免SSH不稳定导致中断${PLAIN}"
    
    # 检查screen是否安装
    if ! command -v screen &> /dev/null; then
        echo -e "${YELLOW}安装screen...${PLAIN}"
        apt-get update && apt-get install -y screen
    fi
    
    read -p "是否使用screen执行批量创建? (Y/n): " use_screen
    if [[ ! "$use_screen" =~ ^[Nn]$ ]]; then
        echo -e "${GREEN}启动screen会话...${PLAIN}"
        screen -S pve_batch_vm -dm bash -c "bash create_vm.sh; exec bash"
        echo -e "${GREEN}批量创建已在screen会话中启动${PLAIN}"
        echo -e "${YELLOW}使用 'screen -r pve_batch_vm' 查看进度${PLAIN}"
    else
        bash create_vm.sh
    fi
}

# 功能：删除指定虚拟机
delete_vm() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}删除指定KVM虚拟机${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    if [ ! -f "pve_delete.sh" ]; then
        echo -e "${YELLOW}下载删除脚本...${PLAIN}"
        download_script "pve_delete.sh" || return 1
    fi
    
    echo -e "${YELLOW}当前虚拟机列表:${PLAIN}"
    qm list
    
    read -p "请输入要删除的VMID (多个VMID用空格分隔): " vm_ids
    if [ -z "$vm_ids" ]; then
        echo -e "${RED}错误：未指定VMID！${PLAIN}"
        return 1
    fi
    
    echo -e "${RED}警告：即将删除以下VMID的虚拟机: ${vm_ids}${PLAIN}"
    read -p "确认删除? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消删除操作${PLAIN}"
        return 0
    fi
    
    for vmid in $vm_ids; do
        echo -e "${YELLOW}删除VMID为 ${vmid} 的虚拟机...${PLAIN}"
        ./pve_delete.sh "$vmid"
    done
    
    echo -e "${GREEN}删除操作完成${PLAIN}"
}

# 功能：删除所有虚拟机
delete_all_vm() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}删除所有KVM虚拟机${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    echo -e "${RED}警告：此操作将删除所有虚拟机和相关配置！${PLAIN}"
    read -p "确认删除所有虚拟机? (yes/N): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}已取消删除操作${PLAIN}"
        return 0
    fi
    
    echo -e "${YELLOW}开始删除所有虚拟机...${PLAIN}"
    
    for vmid in $(qm list | awk '{if(NR>1) print $1}'); do 
        echo -e "${YELLOW}停止并删除VMID为 ${vmid} 的虚拟机...${PLAIN}"
        qm stop $vmid
        qm destroy $vmid
        rm -rf /var/lib/vz/images/$vmid*
    done
    
    echo -e "${YELLOW}清理网络规则...${PLAIN}"
    iptables -t nat -F
    iptables -t filter -F
    service networking restart
    systemctl restart networking.service
    if systemctl list-unit-files | grep -q ndpresponder.service; then
        systemctl restart ndpresponder.service
    fi
    iptables-save | awk '{if($1=="COMMIT"){delete x}}$1=="-A"?!x[$0]++:1' | iptables-restore
    iptables-save > /etc/iptables/rules.v4
    
    echo -e "${YELLOW}删除日志文件...${PLAIN}"
    rm -rf vmlog
    rm -rf vm*
    
    echo -e "${GREEN}所有虚拟机已删除完毕${PLAIN}"
}

# 功能：显示虚拟机列表
list_vm() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}当前KVM虚拟机列表${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    qm list
    
    echo -e "\n${YELLOW}提示：可以使用 'cat vm<VMID>' 查看指定虚拟机的详细信息${PLAIN}"
}

# 功能：环境优化
optimize_env() {
    echo -e "${BLUE}===================${PLAIN}"
    echo -e "${BLUE}PVE环境优化${PLAIN}"
    echo -e "${BLUE}===================${PLAIN}"
    
    echo -e "${YELLOW}开始优化PVE环境...${PLAIN}"
    
    if [ ! -f "build_backend.sh" ]; then
        echo -e "${YELLOW}下载环境优化脚本...${PLAIN}"
        local location=$(check_cn)
        
        if [ "$location" = "cn" ]; then
            curl -L "https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" -o build_backend.sh
        else
            curl -L "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" -o build_backend.sh
        fi
    fi
    
    if [ -f "build_backend.sh" ]; then
        bash build_backend.sh
    else
        echo -e "${RED}脚本下载失败，请检查网络连接！${PLAIN}"
        return 1
    fi
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}=====================================${PLAIN}"
    echo -e "${BLUE}      PVE KVM虚拟机一键管理脚本       ${PLAIN}"
    echo -e "${BLUE}=====================================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 单独创建KVM虚拟机"
    echo -e "${GREEN}2.${PLAIN} 批量创建KVM虚拟机"
    echo -e "${GREEN}3.${PLAIN} 删除指定KVM虚拟机"
    echo -e "${GREEN}4.${PLAIN} 删除所有KVM虚拟机"
    echo -e "${GREEN}5.${PLAIN} 查看KVM虚拟机列表"
    echo -e "${GREEN}6.${PLAIN} PVE环境优化"
    echo -e "${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=====================================${PLAIN}"
    echo -e "项目地址: ${GREEN}https://github.com/oneclickvirt/pve${PLAIN}"
    echo -e "${BLUE}=====================================${PLAIN}"
    read -p "请输入选项 [0-6]: " option
}

# 主函数
main() {
    while true; do
        show_menu
        case "$option" in
            1) create_single_vm ;;
            2) create_batch_vm ;;
            3) delete_vm ;;
            4) delete_all_vm ;;
            5) list_vm ;;
            6) optimize_env ;;
            0) 
                echo -e "${GREEN}感谢使用！再见！${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择！${PLAIN}"
                ;;
        esac
        echo
        read -p "按Enter键返回主菜单..."
    done
}

main 