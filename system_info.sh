#!/bin/bash

# =============================================================================
# Script Name: system_info.sh
# Description: Comprehensive Linux System Information Script
# Author: Trae AI
# Date: $(date +%Y-%m-%d)
# Version: 1.0
# =============================================================================

# --- Global Variables ---
LOG_FILE="/var/log/system_info.log"
CURRENT_USER=$(whoami)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log_message() {
    local message="$1"
    echo -e "${TIMESTAMP} - ${message}" >> "$LOG_FILE"
}

print_header() {
    local title="$1"
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE} $title ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    log_message "Viewing: $title"
}

print_info() {
    local label="$1"
    local value="$2"
    echo -e "${GREEN}${label}:${NC} ${value}"
    log_message "${label}: ${value}"
}

print_section_to_log() {
    echo "------------------------------------------------------------" >> "$LOG_FILE"
}

# --- 1. Permission & Dependency Checks ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root or with sudo.${NC}"
        exit 1
    fi
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
    else
        echo -e "${RED}Error: Unsupported package manager. Please install dependencies manually.${NC}"
        return 1
    fi
}

check_and_install_dependencies() {
    print_header "Checking Dependencies"
    
    local dependencies=("iftop" "net-tools") # net-tools for netstat/ifconfig fallback if needed, though we prefer ip/ss
    local missing_deps=()

    detect_package_manager

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${YELLOW}Dependency $dep not found. Attempting to install...${NC}"
            missing_deps+=("$dep")
        else
            echo -e "${GREEN}Dependency $dep is installed.${NC}"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        if [ -n "$PKG_MANAGER" ]; then
            # Special handling for EPEL on RHEL/CentOS for iftop
            if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
                if ! rpm -q epel-release &> /dev/null; then
                    echo "Installing EPEL release..."
                    $INSTALL_CMD epel-release
                fi
            fi
            
            $INSTALL_CMD "${missing_deps[@]}"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Dependencies installed successfully.${NC}"
                log_message "Dependencies installed: ${missing_deps[*]}"
            else
                echo -e "${RED}Failed to install dependencies. Some features may not work.${NC}"
                log_message "Failed to install dependencies: ${missing_deps[*]}"
            fi
        fi
    fi
}

# --- 2. System Information Functions ---

get_os_info() {
    print_header "Operating System Information"
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        print_info "OS Name" "$NAME"
        print_info "Version" "$VERSION"
        print_info "ID" "$ID"
    elif [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        print_info "Distro" "$DISTRIB_ID"
        print_info "Release" "$DISTRIB_RELEASE"
    else
        print_info "OS Info" "Unknown (Standard files not found)"
    fi
    
    local kernel=$(uname -r)
    print_info "Kernel Version" "$kernel"
    local hostname=$(hostname)
    print_info "Hostname" "$hostname"
    
    # Log raw output for detail
    uname -a >> "$LOG_FILE"
    print_section_to_log
}

get_cpu_info() {
    print_header "CPU Information"
    
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d ':' -f 2 | xargs)
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    
    print_info "CPU Model" "$cpu_model"
    print_info "CPU Cores" "$cpu_cores"
    
    echo -e "\n${YELLOW}--- lscpu output (summary) ---${NC}"
    lscpu | grep -E 'Architecture|CPU\(s\):|Model name|Thread|Core|Socket' | tee -a "$LOG_FILE"
    print_section_to_log
}

get_memory_info() {
    print_header "Memory Usage"
    free -h | tee -a "$LOG_FILE"
    print_section_to_log
}

get_disk_info() {
    print_header "Disk Usage & Mount Points"
    df -h | grep -v "tmpfs" | grep -v "devtmpfs" | tee -a "$LOG_FILE"
    
    echo -e "\n${YELLOW}--- Block Devices (lsblk) ---${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | tee -a "$LOG_FILE"
    print_section_to_log
}

get_uptime_load() {
    print_header "System Uptime & Load"
    uptime | tee -a "$LOG_FILE"
    print_section_to_log
}

# --- 3. Network Information Functions ---

get_network_interfaces() {
    print_header "Network Interfaces"
    if command -v ip &> /dev/null; then
        ip -c addr | tee -a "$LOG_FILE"
    else
        ifconfig | tee -a "$LOG_FILE"
    fi
    print_section_to_log
}

get_network_connections() {
    print_header "Current Network Connections (Listening)"
    if command -v ss &> /dev/null; then
        ss -tulnp | tee -a "$LOG_FILE"
    else
        netstat -tulnp | tee -a "$LOG_FILE"
    fi
    print_section_to_log
}

get_network_latency() {
    print_header "Network Latency Test (Ping 8.8.8.8)"
    echo "Pinging 8.8.8.8 (Google DNS)..."
    ping -c 4 8.8.8.8 | tee -a "$LOG_FILE"
    print_section_to_log
}

get_routing_table() {
    print_header "Routing Table"
    if command -v ip &> /dev/null; then
        ip route | tee -a "$LOG_FILE"
    else
        route -n | tee -a "$LOG_FILE"
    fi
    print_section_to_log
}

monitor_bandwidth() {
    print_header "Real-time Bandwidth Monitoring"
    echo -e "${YELLOW}Starting bandwidth monitor. Press 'q' to quit iftop.${NC}"
    read -p "Press Enter to start..."
    
    if command -v iftop &> /dev/null; then
        iftop
    elif command -v nload &> /dev/null; then
        nload
    else
        echo -e "${RED}Neither iftop nor nload is installed.${NC}"
    fi
    # Note: Interactive tools are not logged to file effectively
    log_message "User launched interactive bandwidth monitor"
}

# --- 4. Main Menu & Execution ---

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Linux 系统信息工具箱                ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "1. 查看系统及内核信息 (OS & Kernel)"
    echo "2. 查看 CPU 信息"
    echo "3. 查看内存使用情况"
    echo "4. 查看磁盘及挂载点"
    echo "5. 查看系统运行时间及负载 (Uptime & Load)"
    echo "6. 查看网络接口信息 (IP/MAC)"
    echo "7. 查看当前网络连接 (Listening Ports)"
    echo "8. 查看路由表"
    echo "9. 测试网络延迟 (Ping Google DNS)"
    echo "10. 实时带宽监控 (iftop/nload)"
    echo "11. 生成完整系统报告"
    echo "0. 退出"
    echo -e "${BLUE}========================================${NC}"
}

generate_full_report() {
    echo -e "${GREEN}正在生成完整系统报告...${NC}"
    log_message "--- 开始生成完整报告 ---"
    get_os_info
    get_cpu_info
    get_memory_info
    get_disk_info
    get_uptime_load
    get_network_interfaces
    get_network_connections
    get_routing_table
    get_network_latency
    log_message "--- 完整报告生成结束 ---"
    echo -e "${GREEN}报告已保存至 $LOG_FILE${NC}"
    read -p "按回车键继续..."
}

main() {
    check_root
    
    # Create log file if not exists
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
    fi
    
    check_and_install_dependencies

    while true; do
        show_menu
        read -p "请输入选项 [0-11]: " choice
        
        case $choice in
            1) get_os_info; read -p "按回车键继续..." ;;
            2) get_cpu_info; read -p "按回车键继续..." ;;
            3) get_memory_info; read -p "按回车键继续..." ;;
            4) get_disk_info; read -p "按回车键继续..." ;;
            5) get_uptime_load; read -p "按回车键继续..." ;;
            6) get_network_interfaces; read -p "按回车键继续..." ;;
            7) get_network_connections; read -p "按回车键继续..." ;;
            8) get_routing_table; read -p "按回车键继续..." ;;
            9) get_network_latency; read -p "按回车键继续..." ;;
            10) monitor_bandwidth ;;
            11) generate_full_report ;;
            0) echo "正在退出..."; exit 0 ;;
            *) echo -e "${RED}无效选项，请重试。${NC}"; sleep 1 ;;
        esac
    done
}

# Start the script
main
