#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="$SCRIPT_DIR"
NETWORK_NAME="shared-network"
CONTAINER_NAME="nginx-proxy"

# 检测容器引擎
CONTAINER_ENGINE=""
COMPOSE_CMD=""

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_question() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

# 退出函数
exit_on_error() {
    log_error "$1"
    exit 1
}

# 检查执行用户和环境
check_execution_environment() {
    local current_user=$(whoami)
    log_info "当前执行用户: $current_user"
    
    # 检查是否通过sudo -u执行
    if [[ -n "$SUDO_USER" && "$current_user" != "$SUDO_USER" ]]; then
        log_info "检测到通过 sudo -u $current_user 执行"
        log_info "原始用户: $SUDO_USER"
    fi
    
    # 检查工作目录权限
    if [[ ! -w "$SCRIPT_DIR" ]]; then
        exit_on_error "当前目录 $SCRIPT_DIR 不可写，请检查 $current_user 用户权限"
    fi
    
    # 为非交互式环境设置必要的环境变量
    if [[ -z "$HOME" ]]; then
        export HOME="/home/$current_user"
        log_info "设置 HOME=$HOME"
    fi
    
    # 确保HOME目录存在
    if [[ ! -d "$HOME" ]]; then
        log_warn "用户HOME目录 $HOME 不存在，尝试创建..."
        mkdir -p "$HOME" || exit_on_error "无法创建HOME目录"
    fi
    
    # 设置XDG相关环境变量
    if [[ -z "$XDG_RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        log_info "设置 XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    fi
    
    if [[ -z "$XDG_CONFIG_HOME" ]]; then
        export XDG_CONFIG_HOME="$HOME/.config"
        log_info "设置 XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    fi
    
    # 确保必要目录存在
    mkdir -p "$XDG_CONFIG_HOME" 2>/dev/null || true
}

# 检查并优化Podman环境
optimize_podman_env() {
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        log_info "检测到Podman环境，优化配置..."
        
        local current_user=$(whoami)
        
        # 检查lingering状态
        if command -v loginctl &> /dev/null; then
            if ! loginctl show-user "$current_user" -p Linger 2>/dev/null | grep -q "Linger=yes"; then
                log_warn "用户 $current_user 的lingering未启用"
                if [[ -n "$SUDO_USER" ]]; then
                    log_info "请以root用户运行: loginctl enable-linger $current_user"
                else
                    log_info "建议运行: sudo loginctl enable-linger $current_user"
                fi
            fi
        fi
        
        # 创建containers配置目录
        local containers_config_dir="$XDG_CONFIG_HOME/containers"
        mkdir -p "$containers_config_dir"
        
        # 配置containers.conf
        local containers_conf="$containers_config_dir/containers.conf"
        if [[ ! -f "$containers_conf" ]] || ! grep -q "cgroup_manager" "$containers_conf"; then
            log_info "配置Podman使用cgroupfs管理器..."
            
            # 备份现有配置
            if [[ -f "$containers_conf" ]]; then
                cp "$containers_conf" "$containers_conf.backup.$(date +%s)"
            fi
            
            # 创建配置文件
            cat > "$containers_conf" << 'EOF'
[containers]
cgroup_manager = "cgroupfs"
events_logger = "file"
log_driver = "k8s-file"

[engine]
cgroup_manager = "cgroupfs"
runtime = "crun"

[network]
network_backend = "cni"
EOF
            log_info "已配置Podman containers.conf"
        fi
        
        # 设置额外的Podman环境变量
        export CONTAINERS_CONF="$containers_conf"
        export CONTAINERS_STORAGE_CONF="$containers_config_dir/storage.conf"
        
        # 如果XDG_RUNTIME_DIR不存在，尝试创建或使用替代方案
        if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
            log_warn "XDG_RUNTIME_DIR ($XDG_RUNTIME_DIR) 不存在"
            
            # 尝试使用用户特定的临时目录
            local alt_runtime_dir="/tmp/podman-run-$(id -u)"
            mkdir -p "$alt_runtime_dir"
            export XDG_RUNTIME_DIR="$alt_runtime_dir"
            log_info "使用替代运行时目录: $XDG_RUNTIME_DIR"
        fi
        
        # 检查podman是否可以正常运行
        if ! podman info >/dev/null 2>&1; then
            log_warn "Podman初始化检查失败，这可能是正常的首次运行"
        fi
    fi
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        # 如果是通过sudo -u执行，则不是真正的root
        if [[ -z "$SUDO_USER" ]]; then
            exit_on_error "请不要直接使用root用户运行此脚本"
        fi
    fi
}

# 检测容器引擎和Compose工具
detect_container_engine() {
    if command -v podman &> /dev/null; then
        CONTAINER_ENGINE="podman"
        if command -v podman-compose &> /dev/null; then
            COMPOSE_CMD="podman-compose"
        else
            exit_on_error "Podman已安装但未找到podman-compose，请安装podman-compose"
        fi
        log_info "检测到容器引擎: Podman"
        
        # 优化Podman环境
        optimize_podman_env
        
    elif command -v docker &> /dev/null; then
        CONTAINER_ENGINE="docker"
        if command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
        elif command -v docker compose &> /dev/null; then
            COMPOSE_CMD="docker compose"
        else
            exit_on_error "Docker已安装但未找到docker-compose，请安装Docker Compose"
        fi
        log_info "检测到容器引擎: Docker"
    else
        exit_on_error "未找到容器引擎 (Podman或Docker)，请先安装"
    fi
}

# 静默执行容器命令（抑制警告）
run_container_cmd() {
    local cmd="$1"
    shift
    
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        # 对于Podman，重定向stderr来过滤cgroup警告
        $cmd "$@" 2> >(grep -v -E "(cgroupv2 manager|systemd user session|enable-linger|cgroup-manager=cgroupfs|WARN\[)" >&2) || return $?
    else
        $cmd "$@"
    fi
}

# 检查curl是否可用
check_curl() {
    if ! command -v curl &> /dev/null; then
        exit_on_error "未找到curl命令，请先安装curl"
    fi
}

# 主逻辑开始
main() {
    check_root
    check_execution_environment
    check_curl
    detect_container_engine
    
    log_info "脚本工作目录: $NGINX_DIR"
    
    # 检查是否已存在Nginx容器
    if ! $CONTAINER_ENGINE ps -a --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        log_info "未检测到Nginx容器，开始初始化..."
        init_nginx
    else
        log_info "检测到现有的Nginx容器"
        
        # 检查容器是否运行中
        if ! $CONTAINER_ENGINE ps --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
            log_warn "Nginx容器已停止，正在启动..."
            cd "$NGINX_DIR"
            if ! $COMPOSE_CMD up -d; then
                exit_on_error "启动Nginx容器失败"
            fi
        fi
    fi
    
    # 主循环
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                add_backend_service
                ;;
            2)
                list_services
                ;;
            3)
                remove_service
                ;;
            4)
                log_info "重启Nginx..."
                cd "$NGINX_DIR"
                if ! $COMPOSE_CMD restart; then
                    exit_on_error "重启Nginx失败"
                fi
                ;;
            5)
                echo "选择日志类型："
                echo "1. 访问日志"
                echo "2. 错误日志"
                echo "3. 容器日志"
                read -p "请选择 [1-3]: " log_choice
                
                case $log_choice in
                    1) 
                        if ! $CONTAINER_ENGINE exec $CONTAINER_NAME tail -f /var/log/nginx/access.log; then
                            exit_on_error "查看访问日志失败"
                        fi
                        ;;
                    2) 
                        if ! $CONTAINER_ENGINE exec $CONTAINER_NAME tail -f /var/log/nginx/error.log; then
                            exit_on_error "查看错误日志失败"
                        fi
                        ;;
                    3) 
                        cd "$NGINX_DIR"
                        if ! $COMPOSE_CMD logs -f; then
                            exit_on_error "查看容器日志失败"
                        fi
                        ;;
                    *) 
                        log_error "无效选择" 
                        ;;
                esac
                ;;
            6)
                log_info "更新Cloudflare IP并重新生成基础配置..."
                generate_base_config
                cd "$NGINX_DIR"
                if ! $COMPOSE_CMD restart; then
                    exit_on_error "重启Nginx失败"
                fi
                ;;
            7)
                log_info "测试Nginx配置..."
                if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t; then
                    log_info "配置测试通过"
                else
                    log_error "配置测试失败"
                fi
                ;;
            8)
                show_container_status
                ;;
            0)
                log_info "退出脚本"
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        read -p "按Enter键继续..." 
    done
}

# 运行主程序
main "$@"
