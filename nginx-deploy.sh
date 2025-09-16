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

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
       # exit_on_error "请不要使用root用户运行此脚本"
       log_info "root用户运行"
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

# 检查curl是否可用
check_curl() {
    if ! command -v curl &> /dev/null; then
        exit_on_error "未找到curl命令，请先安装curl"
    fi
}

# 创建网络
create_network() {
    if ! $CONTAINER_ENGINE network inspect $NETWORK_NAME &> /dev/null; then
        log_info "创建网络: $NETWORK_NAME"
        if ! $CONTAINER_ENGINE network create $NETWORK_NAME; then
            exit_on_error "创建网络失败"
        fi
    else
        log_info "网络 $NETWORK_NAME 已存在"
    fi
}

# 获取Cloudflare IP列表
update_cf_ips() {
    log_info "获取Cloudflare IP列表..."
    
    # 检查网络连接
    if ! curl -s --connect-timeout 5 https://www.cloudflare.com &> /dev/null; then
        exit_on_error "无法连接到Cloudflare，请检查网络连接"
    fi
    
    # 获取IPv4列表
    CF_IPS_V4=$(curl -s --connect-timeout 10 --max-time 20 https://www.cloudflare.com/ips-v4)
    if [[ $? -ne 0 || -z "$CF_IPS_V4" ]]; then
        exit_on_error "获取Cloudflare IPv4列表失败，请检查网络连接或稍后重试"
    fi
    
    # 获取IPv6列表
    CF_IPS_V6=$(curl -s --connect-timeout 10 --max-time 20 https://www.cloudflare.com/ips-v6)
    if [[ $? -ne 0 || -z "$CF_IPS_V6" ]]; then
        exit_on_error "获取Cloudflare IPv6列表失败，请检查网络连接或稍后重试"
    fi
    
    # 验证获取的内容格式是否正确（应该包含IP地址）
    if ! echo "$CF_IPS_V4" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' &> /dev/null; then
        exit_on_error "获取到的Cloudflare IPv4列表格式不正确"
    fi
    
    log_info "成功获取Cloudflare IP列表"
}

# 生成Nginx基础配置
generate_base_config() {
    update_cf_ips
    
    log_info "生成Nginx配置文件..."
    
    cat > "$NGINX_DIR/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    # 基本设置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # 日志设置
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    '"$host" "$http_cf_ray"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Cloudflare真实IP设置
EOF

    # 添加CF IPv4列表
    echo "$CF_IPS_V4" | while IFS= read -r ip; do
        if [[ ! -z "$ip" ]]; then
            echo "    set_real_ip_from $ip;" >> "$NGINX_DIR/nginx.conf"
        fi
    done

    # 添加CF IPv6列表
    echo "$CF_IPS_V6" | while IFS= read -r ip; do
        if [[ ! -z "$ip" ]]; then
            echo "    set_real_ip_from $ip;" >> "$NGINX_DIR/nginx.conf"
        fi
    done

    cat >> "$NGINX_DIR/nginx.conf" << 'EOF'
    real_ip_header CF-Connecting-IP;

    # 默认服务器 - 阻止IP直接访问和未知域名
    server {
        listen 80 default_server;
        server_name _;
        
        # 记录被阻止的访问
        access_log /var/log/nginx/blocked.log main;
        
        # 返回444直接关闭连接
        return 444;
    }

    # 健康检查服务器（仅本地访问）
    server {
        listen 8080;
        server_name localhost;
        
        location /health {
            access_log off;
            return 200 "nginx healthy\n";
            add_header Content-Type text/plain;
        }
    }

EOF

    # 包含其他配置文件
    echo "    # 包含站点配置" >> "$NGINX_DIR/nginx.conf"
    echo "    include /etc/nginx/conf.d/*.conf;" >> "$NGINX_DIR/nginx.conf"
    echo "}" >> "$NGINX_DIR/nginx.conf"
    
    log_info "Nginx配置文件生成完成"
}

# 创建Docker/Podman Compose文件
create_compose_file() {
    log_info "生成Docker Compose文件..."
    
    # 根据容器引擎选择不同的配置
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        cat > "$NGINX_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "8080:8080"  # 健康检查端口
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro,Z
      - ./conf.d:/etc/nginx/conf.d:ro,Z
      - nginx-logs:/var/log/nginx:Z
    networks:
      - shared-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  nginx-logs:

networks:
  shared-network:
    external: true
EOF
    else
        cat > "$NGINX_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "8080:8080"  # 健康检查端口
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - nginx-logs:/var/log/nginx
    networks:
      - shared-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  nginx-logs:

networks:
  shared-network:
    external: true
EOF
    fi
    
    log_info "Docker Compose文件生成完成"
}

# 添加新的后端服务
add_backend_service() {
    log_question "请输入要添加的服务信息："
    
    read -p "子域名 (如: gpt-load): " subdomain
    read -p "主域名 (如: 141464.xyz): " domain
    read -p "后端容器名 (如: gpt-load-app): " container_name
    read -p "后端端口 (如: 3001): " port
    
    if [[ -z "$subdomain" || -z "$domain" || -z "$container_name" || -z "$port" ]]; then
        log_error "所有字段都必须填写"
        return 1
    fi
    
    # 验证端口是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "端口必须是1-65535之间的数字"
        return 1
    fi
    
    FULL_DOMAIN="$subdomain.$domain"
    CONFIG_FILE="$NGINX_DIR/conf.d/$subdomain.conf"
    
    # 检查配置文件是否已存在
    if [[ -f "$CONFIG_FILE" ]]; then
        read -p "配置文件已存在，是否覆盖? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "取消添加服务"
            return 0
        fi
    fi
    
    log_info "生成配置文件: $CONFIG_FILE"
    
    cat > "$CONFIG_FILE" << EOF
# $FULL_DOMAIN 配置
upstream ${subdomain}-backend {
    server ${container_name}:${port};
}

server {
    listen 80;
    server_name ${FULL_DOMAIN};

    # 安全检查：确保请求来自Cloudflare
    if (\$http_cf_connecting_ip = "") {
        return 403 "Direct access not allowed";
    }

    # 访问日志
    access_log /var/log/nginx/${subdomain}_access.log main;
    error_log /var/log/nginx/${subdomain}_error.log;

    location / {
        proxy_pass http://${subdomain}-backend;
        
        # 代理头设置
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_cf_visitor_scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        # Cloudflare特殊头传递
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_set_header CF-RAY \$http_cf_ray;
        proxy_set_header CF-Visitor \$http_cf_visitor;
        
        # WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 8 8k;
        proxy_busy_buffers_size 16k;
    }
}
EOF

    log_info "已创建配置文件: $FULL_DOMAIN -> $container_name:$port"
    
    # 检查配置并重载
    if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t 2>/dev/null; then
        if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -s reload; then
            log_info "Nginx配置已重载"
            log_info "请确保在Cloudflare中添加DNS记录："
            log_info "类型: A, 名称: $subdomain, 内容: 服务器IP, 代理: 开启"
        else
            exit_on_error "Nginx重载失败"
        fi
    else
        exit_on_error "Nginx配置测试失败，请检查配置文件"
    fi
}

# 列出现有服务
list_services() {
    log_info "当前已配置的服务："
    if [[ -d "$NGINX_DIR/conf.d" ]] && [[ -n "$(ls -A $NGINX_DIR/conf.d/*.conf 2>/dev/null)" ]]; then
        for conf_file in "$NGINX_DIR/conf.d"/*.conf; do
            if [[ -f "$conf_file" ]]; then
                filename=$(basename "$conf_file" .conf)
                domain=$(grep "server_name" "$conf_file" | head -1 | awk '{print $2}' | tr -d ';')
                upstream=$(grep "server " "$conf_file" | grep -v "server_name" | head -1 | awk '{print $2}' | tr -d ';')
                echo "  - $filename: $domain -> $upstream"
            fi
        done
    else
        echo "  暂无配置的服务"
    fi
}

# 删除服务
remove_service() {
    list_services
    echo
    read -p "请输入要删除的服务名称 (输入配置文件名，不含.conf): " service_name
    
    if [[ -z "$service_name" ]]; then
        log_error "服务名称不能为空"
        return 1
    fi
    
    CONFIG_FILE="$NGINX_DIR/conf.d/$service_name.conf"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    
    read -p "确认删除服务 $service_name? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if rm -f "$CONFIG_FILE"; then
            if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t 2>/dev/null; then
                if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -s reload; then
                    log_info "服务 $service_name 已删除并重载配置"
                else
                    exit_on_error "删除服务后Nginx重载失败"
                fi
            else
                exit_on_error "删除服务后Nginx配置测试失败"
            fi
        else
            exit_on_error "删除配置文件失败"
        fi
    else
        log_info "取消删除操作"
    fi
}

# 初始化Nginx
init_nginx() {
    log_info "初始化Nginx..."
    log_info "工作目录: $NGINX_DIR"
    
    # 创建目录
    if ! mkdir -p "$NGINX_DIR/conf.d"; then
        exit_on_error "创建配置目录失败"
    fi
    
    # 生成配置文件
    generate_base_config
    create_compose_file
    
    # 创建网络
    create_network
    
    # 启动容器
    cd "$NGINX_DIR"
    log_info "启动Nginx容器..."
    if ! $COMPOSE_CMD up -d; then
        exit_on_error "启动Nginx容器失败"
    fi
    
    # 等待启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查健康状态
    local retry_count=0
    local max_retries=6
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -f http://localhost:8080/health &>/dev/null; then
            log_info "Nginx启动成功！"
            log_info "健康检查: http://localhost:8080/health"
            return 0
        fi
        
        ((retry_count++))
        log_warn "健康检查失败，重试 $retry_count/$max_retries..."
        sleep 5
    done
    
    exit_on_error "Nginx启动失败，请检查日志: $COMPOSE_CMD -f $NGINX_DIR/docker-compose.yml logs"
}

# 主菜单
show_menu() {
    echo
    echo "========== Nginx 部署管理脚本 ($CONTAINER_ENGINE) =========="
    echo "工作目录: $NGINX_DIR"
    echo "1. 添加后端服务"
    echo "2. 列出现有服务"
    echo "3. 删除服务"
    echo "4. 重启Nginx"
    echo "5. 查看日志"
    echo "6. 更新Cloudflare IP"
    echo "7. 测试配置"
    echo "8. 查看容器状态"
    echo "0. 退出"
    echo "=================================================="
}

# 查看容器状态
show_container_status() {
    log_info "容器状态:"
    if ! $CONTAINER_ENGINE ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|$CONTAINER_NAME)"; then
        log_warn "未找到相关容器"
    fi
    echo
    
    log_info "网络状态:"
    if $CONTAINER_ENGINE network inspect $NETWORK_NAME &>/dev/null; then
        echo "网络 $NETWORK_NAME 存在"
        if ! $CONTAINER_ENGINE network inspect $NETWORK_NAME --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'; then
            log_warn "获取网络信息失败"
        fi
    else
        echo "网络 $NETWORK_NAME 不存在"
    fi
}

# 主逻辑
main() {
    check_root
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
