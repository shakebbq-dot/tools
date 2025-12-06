#!/bin/bash

# =============================================================================
# Script Name: bandwidth_test.sh
# Description: Advanced Bandwidth Testing Tool for Linux Servers
# Author: Trae AI
# Date: $(date +%Y-%m-%d)
# Version: 1.0
# =============================================================================

# --- Global Variables ---
LOG_FILE="/var/log/bandwidth_test.log"
REPORT_DIR="./bandwidth_reports"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
DATE_STR=$(date "+%Y%m%d_%H%M%S")

# Default Configuration
TEST_DURATION=30
PARALLEL_STREAMS=4
TARGET_HOST="" # User must provide or select a public server
TARGET_PORT=5201

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Public iperf3 Servers List (Fallbacks) ---
# Note: These are common public servers, availability may vary.
declare -A PUBLIC_SERVERS
PUBLIC_SERVERS["Ping.online (法国)"]="ping.online.net"
PUBLIC_SERVERS["Bouygues Telecom (法国)"]="lyo.bbr.iperf.bytel.fr"
PUBLIC_SERVERS["Clouvider (英国-伦敦)"]="lon.speedtest.clouvider.net"
PUBLIC_SERVERS["Clouvider (美国-洛杉矶)"]="la.speedtest.clouvider.net"
PUBLIC_SERVERS["Clouvider (美国-纽约)"]="nyc.speedtest.clouvider.net"
PUBLIC_SERVERS["Clouvider (荷兰-阿姆斯特丹)"]="ams.speedtest.clouvider.net"
PUBLIC_SERVERS["Leaseweb (德国-法兰克福)"]="speedtest.fra1.de.leaseweb.net"

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
}

print_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "本脚本必须以 root 用户或使用 sudo 运行。"
        exit 1
    fi
}

# --- Dependency Management ---

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
        print_error "不支持的包管理器。请手动安装依赖。"
        return 1
    fi
}

check_dependencies() {
    print_header "正在检查依赖"
    
    local dependencies=("iperf3" "jq" "bc")
    local missing_deps=()

    detect_package_manager

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_warning "未找到依赖 $dep。准备安装..."
            missing_deps+=("$dep")
        else
            print_info "依赖 $dep 已安装。"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        if [ -n "$PKG_MANAGER" ]; then
             # Special handling for EPEL on RHEL/CentOS for jq/iperf3
            if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
                if ! rpm -q epel-release &> /dev/null; then
                    echo "正在安装 EPEL release..."
                    $INSTALL_CMD epel-release
                fi
            fi

            print_info "正在安装缺失依赖: ${missing_deps[*]}"
            $INSTALL_CMD "${missing_deps[@]}"
            
            if [ $? -eq 0 ]; then
                print_info "依赖安装成功。"
            else
                print_error "安装依赖失败。请手动安装: ${missing_deps[*]}"
                exit 1
            fi
        fi
    fi
    
    mkdir -p "$REPORT_DIR"
}

# --- Test Functions ---

select_server() {
    print_header "选择 iperf3 目标服务器"
    echo "1. 输入自定义服务器 IP/域名"
    
    local i=2
    local server_keys=("${!PUBLIC_SERVERS[@]}")
    for key in "${server_keys[@]}"; do
        echo "$i. $key (${PUBLIC_SERVERS[$key]})"
        ((i++))
    done
    
    read -p "请输入选项: " choice
    
    if [ "$choice" == "1" ]; then
        read -p "请输入服务器 IP/域名: " custom_host
        TARGET_HOST="$custom_host"
    elif [[ "$choice" -ge 2 && "$choice" -le ${#server_keys[@]}+1 ]]; then
        local index=$((choice-2))
        local selected_key="${server_keys[$index]}"
        TARGET_HOST="${PUBLIC_SERVERS[$selected_key]}"
    else
        print_error "无效的选择。"
        return 1
    fi
    
    print_info "已选择目标: $TARGET_HOST"
}

run_iperf_test() {
    local mode="$1" # upload, download, bidirectional
    local protocol="$2" # tcp, udp
    local reverse_flag=""
    
    if [ "$mode" == "download" ]; then
        reverse_flag="-R"
    fi
    
    local json_output="${REPORT_DIR}/iperf_${mode}_${protocol}_${DATE_STR}.json"
    local error_log="${REPORT_DIR}/iperf_error.log"
    
    print_info "正在启动 $mode 测试 ($protocol)..."
    print_info "持续时间: ${TEST_DURATION}秒, 并行流数: $PARALLEL_STREAMS"
    
    local max_retries=3
    local retry_delay=3
    local success=0
    
    # Port range to try (start with selected, then increment)
    local start_port=$TARGET_PORT
    local end_port=$((start_port + 9)) # Try up to 10 ports (e.g., 5201-5210)
    
    for ((port=start_port; port<=end_port; port++)); do
        # Reset retry count for each port
        for ((try=1; try<=max_retries; try++)); do
            local cmd="iperf3 -c $TARGET_HOST -p $port -t $TEST_DURATION -P $PARALLEL_STREAMS -J"
            
            if [ "$protocol" == "udp" ]; then
                # Use a safer default for UDP (100M) instead of unlimited to avoid being blocked
                # If user wants higher, they can modify script, but 100M is good for loss/jitter test
                cmd="$cmd -u -b 100M" 
            fi
            
            if [ -n "$reverse_flag" ]; then
                cmd="$cmd $reverse_flag"
            fi
            
            if [ $try -gt 1 ]; then
                print_warning "尝试 #$try (端口 $port)..."
            else
                echo "正在尝试端口 $port: $cmd"
            fi
            
            # Run command, capture stderr to log
            eval "$cmd" > "$json_output" 2> "$error_log"
            local exit_code=$?
            
            if [ $exit_code -eq 0 ]; then
                # Double check if JSON is valid (sometimes iperf3 returns 0 but writes error to JSON)
                local json_error=$(jq -r '.error' "$json_output" 2>/dev/null)
                if [[ "$json_error" != "null" && -n "$json_error" ]]; then
                     print_error "iPerf3 内部错误: $json_error"
                     # Treat as failure, retry
                else
                    success=1
                    break 2 # Break both loops
                fi
            else
                # Check error log for "busy"
                if grep -q "busy" "$error_log"; then
                    print_warning "服务器正忙 (端口 $port)，等待 ${retry_delay} 秒后重试..."
                    sleep $retry_delay
                elif grep -q "Connection refused" "$error_log"; then
                    print_warning "端口 $port 连接被拒绝，尝试下一个端口..."
                    break # Try next port immediately
                else
                    # Other errors
                    local err_msg=$(cat "$error_log")
                    print_warning "测试出错: $err_msg"
                    sleep $retry_delay
                fi
            fi
        done
    done
    
    if [ $success -eq 0 ]; then
        print_error "测试最终失败。所有尝试均未成功。"
        print_error "最后一次错误信息:"
        cat "$error_log"
        rm -f "$json_output"
        return 1
    fi
    
    parse_and_display_results "$json_output" "$mode" "$protocol"
}

parse_and_display_results() {
    local json_file="$1"
    local mode="$2"
    local protocol="$3"
    
    if [ ! -f "$json_file" ]; then
        print_error "未找到结果文件。"
        return
    fi
    
    print_header "测试结果: $mode ($protocol)"
    
    # Extract data using jq
    local sent_mb=$(jq '.end.sum_sent.bytes / 1000000' "$json_file")
    local received_mb=$(jq '.end.sum_received.bytes / 1000000' "$json_file")
    local bits_per_second=$(jq '.end.sum_received.bits_per_second' "$json_file")
    local bandwidth_mbps=$(echo "scale=2; $bits_per_second / 1000000" | bc)
    
    # Additional stats
    local cpu_host=$(jq '.end.cpu_utilization_percent.host_total' "$json_file")
    local cpu_remote=$(jq '.end.cpu_utilization_percent.remote_total' "$json_file")
    
    echo -e "${CYAN}传输数据:${NC} ${sent_mb} MB (发送) / ${received_mb} MB (接收)"
    echo -e "${CYAN}带宽速率:${NC} ${GREEN}${bandwidth_mbps} Mbps${NC}"
    echo -e "${CYAN}CPU 使用率:${NC} 本机: ${cpu_host}%, 远端: ${cpu_remote}%"
    
    if [ "$protocol" == "udp" ]; then
        local lost_packets=$(jq '.end.sum.lost_packets' "$json_file")
        local total_packets=$(jq '.end.sum.packets' "$json_file")
        local loss_percent=$(echo "scale=2; ($lost_packets / $total_packets) * 100" | bc)
        local jitter=$(jq '.end.sum.jitter_ms' "$json_file")
        
        echo -e "${CYAN}网络抖动:${NC} ${jitter} ms"
        echo -e "${CYAN}丢包情况:${NC} ${lost_packets}/${total_packets} (${loss_percent}%)"
    fi
    
    # Append summary to report log
    {
        echo "测试: $mode ($protocol)"
        echo "时间: $TIMESTAMP"
        echo "目标: $TARGET_HOST"
        echo "带宽: $bandwidth_mbps Mbps"
        echo "-----------------------------------"
    } >> "$LOG_FILE"
}

generate_visualization() {
    local report_file="${REPORT_DIR}/report_${DATE_STR}.txt"
    print_header "生成可视化报告"
    
    echo "========================================" > "$report_file"
    echo "           带宽测试报告                 " >> "$report_file"
    echo "========================================" >> "$report_file"
    echo "日期: $TIMESTAMP" >> "$report_file"
    echo "目标: $TARGET_HOST" >> "$report_file"
    echo "" >> "$report_file"
    
    # Simple ASCII Bar Chart logic could go here, or just summary for now
    grep -h "测试:" "$LOG_FILE" | tail -n 5 >> "$report_file"
    
    echo -e "${GREEN}报告已保存至 $report_file${NC}"
}


# --- Menus ---

configure_settings() {
    print_header "设置"
    read -p "请输入测试时长 (秒) [当前: $TEST_DURATION]: " duration
    if [[ "$duration" =~ ^[0-9]+$ ]]; then
        TEST_DURATION=$duration
    fi
    
    read -p "请输入并行流数 [当前: $PARALLEL_STREAMS]: " streams
    if [[ "$streams" =~ ^[0-9]+$ ]]; then
        PARALLEL_STREAMS=$streams
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}    服务器带宽测试工具 (iperf3)         ${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo -e "目标服务器: ${YELLOW}${TARGET_HOST:-未选择}${NC}"
        echo -e "配置: ${TEST_DURATION}秒 | ${PARALLEL_STREAMS}线程"
        echo "----------------------------------------"
        echo "1. 选择/更改目标服务器"
        echo "2. 配置测试参数 (时长/线程数)"
        echo "3. 运行上传测试 (TCP)"
        echo "4. 运行下载测试 (TCP)"
        echo "5. 运行 UDP 测试 (上传/丢包/抖动)"
        echo "6. 运行全套测试 (上传/下载 TCP + UDP)"
        echo "7. 查看历史报告"
        echo "0. 退出"
        echo "----------------------------------------"
        read -p "请输入选项: " choice
        
        case $choice in
            1) select_server ;;
            2) configure_settings ;;
            3) 
                [ -z "$TARGET_HOST" ] && select_server
                run_iperf_test "upload" "tcp"
                read -p "按回车键继续..." 
                ;;
            4) 
                [ -z "$TARGET_HOST" ] && select_server
                run_iperf_test "download" "tcp"
                read -p "按回车键继续..." 
                ;;
            5) 
                [ -z "$TARGET_HOST" ] && select_server
                run_iperf_test "upload" "udp"
                read -p "按回车键继续..." 
                ;;
            6)
                [ -z "$TARGET_HOST" ] && select_server
                run_iperf_test "upload" "tcp"
                run_iperf_test "download" "tcp"
                run_iperf_test "upload" "udp"
                generate_visualization
                read -p "按回车键继续..." 
                ;;
            7)
                ls -l "$REPORT_DIR"
                read -p "按回车键继续..."
                ;;
            0) exit 0 ;;
            *) echo "无效的选项。" ;;
        esac
    done
}

# --- Main Execution ---
check_root
check_dependencies
main_menu
