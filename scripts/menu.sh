#!/bin/bash

# 主菜单
show_menu() {
    echo
    echo "========== Nginx + Let's Encrypt 部署管理脚本 =========="
    echo "工作目录: $NGINX_DIR"
    echo "1. 添加/更新服务"
    echo "2. 列出现有服务"
    echo "3. 删除服务"
    echo "4. 重启所有服务"
    echo "5. 查看日志"
    echo "6. 手动续订所有证书"
    echo "7. 测试Nginx配置"
    echo "8. 查看容器状态"
    echo "9. 查看已安装证书"
    echo "0. 退出"
    echo "=================================================="
}

# 查看容器状态
show_container_status() {
    log_info "容器状态:"
    $CONTAINER_ENGINE ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    log_info "网络状态:"
    $CONTAINER_ENGINE network inspect $NETWORK_NAME --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
}


# 初始化Nginx
init_nginx() {
    log_info "初始化Nginx..."
    log_info "工作目录: $NGINX_DIR"
    
    mkdir -p "$NGINX_DIR/conf.d"
    mkdir -p "$NGINX_DIR/data/certbot/www"
    mkdir -p "$NGINX_DIR/data/certbot/certs"
    mkdir -p "$NGINX_DIR/data/nginx-logs"
    
    generate_base_config
    create_compose_file
    create_network
    
    cd "$NGINX_DIR"
    log_info "启动Nginx容器..."
    if ! $COMPOSE_CMD up -d; then
        exit_on_error "启动Nginx容器失败"
    fi
    
    log_info "等待服务启动..."
    sleep 10
    
    local retry_count=0
    local max_retries=6
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -sf http://localhost:8080/health &>/dev/null; then
            log_info "Nginx启动成功！健康检查: http://localhost:8080/health"
            return 0
        fi
        ((retry_count++))
        log_warn "健康检查失败，重试 $retry_count/$max_retries..."
        sleep 5
    done
    
    exit_on_error "Nginx启动失败，请检查日志: $COMPOSE_CMD logs nginx-proxy"
}


# 主循环
run_main_loop() {
    check_root
    check_curl
    
    detect_container_engine
    
    log_info "脚本工作目录: $NGINX_DIR"
    
    if ! $CONTAINER_ENGINE ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_info "未检测到Nginx容器，开始初始化..."
        init_nginx
    else
        log_info "检测到现有的Nginx容器"
        cd "$NGINX_DIR"
        if ! $COMPOSE_CMD up -d; then
            log_warn "确保所有服务已启动..."
        fi
    fi
    
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice
        
        case $choice in
            1) add_backend_service ;;
            2) list_services ;;
            3) remove_service ;;
            4)
                log_info "重启所有服务..."
                cd "$NGINX_DIR"
                if ! $COMPOSE_CMD restart; then log_error "重启失败"; fi
                ;;
            5)
                echo "选择日志类型："
                echo "1. Nginx访问日志"
                echo "2. Nginx错误日志"
                echo "3. Nginx容器日志"
                echo "4. Certbot容器日志"
                read -p "请选择 [1-4]: " log_choice
                
                case $log_choice in
                    1) $CONTAINER_ENGINE exec $CONTAINER_NAME tail -f /var/log/nginx/access.log ;;
                    2) $CONTAINER_ENGINE exec $CONTAINER_NAME tail -f /var/log/nginx/error.log ;;
                    3) cd "$NGINX_DIR"; $COMPOSE_CMD logs -f nginx-proxy ;;
                    4) cd "$NGINX_DIR"; $COMPOSE_CMD logs -f certbot-service ;;
                    *) log_error "无效选择" ;;
                esac
                ;;
            6)
                log_info "手动续订所有SSL证书..."
                cd "$NGINX_DIR"; $COMPOSE_CMD run --rm certbot renew
                ;;
            7)
                log_info "测试Nginx配置..."
                $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t
                ;;
            8)
                show_container_status
                ;;
            9)
                show_certificates
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