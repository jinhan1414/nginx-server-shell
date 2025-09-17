#!/bin/bash

# 请求证书
request_certificate() {
    local domain="$1"
    local email="$2"
    
    log_info "为域名 $domain 申请SSL证书..."
    
    # 确保Nginx容器正在运行以进行反向代理
    if ! $CONTAINER_ENGINE ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Nginx容器未运行，正在启动..."
        cd "$NGINX_DIR"
        if ! $COMPOSE_CMD up -d nginx; then
            log_error "启动Nginx失败，无法申请证书"
            return 1
        fi
        sleep 5
    fi

    # 使用 standalone 模式，临时暴露端口让 Nginx 可以反向代理
    local certbot_cmd="$COMPOSE_CMD run --rm -p 8081:8081 certbot certonly --standalone --http-01-port 8081 --non-interactive --agree-tos -m $email -d $domain"

    if eval $certbot_cmd; then
        log_info "证书申请成功: $domain"
        return 0
    else
        log_error "证书申请失败: $domain"
        log_error "请检查: 1. 域名解析是否正确指向本机IP. 2. 防火墙是否开放80端口."
        return 1
    fi
}

# 显示已安装的证书
show_certificates() {
    log_info "正在查询已安装的证书..."
    cd "$NGINX_DIR"
    $COMPOSE_CMD run --rm certbot certificates
}