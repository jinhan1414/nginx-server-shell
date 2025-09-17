#!/bin/bash

# 请求证书
request_certificate() {
    local domain="$1"
    local email="$2"
    
    log_info "为域名 $domain 申请SSL证书..."
    
    # 1. 创建一个临时的Nginx配置文件，专门用于处理当前域名的ACME挑战
    local temp_conf_file="$NGINX_DIR/conf.d/temp-validation-${domain}.conf"
    log_info "创建临时验证配置: ${temp_conf_file}"
    cat > "$temp_conf_file" << EOF
server {
    listen 80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}
EOF

    # 2. 确保Nginx容器运行并重载配置以应用临时文件
    if ! $CONTAINER_ENGINE ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Nginx容器未运行，正在启动..."
        cd "$NGINX_DIR"; $COMPOSE_CMD up -d nginx || { log_error "启动Nginx失败"; rm -f "$temp_conf_file"; return 1; }
        sleep 5
    else
        log_info "重载Nginx以应用临时验证配置..."
        $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -s reload || { log_error "Nginx重载失败"; rm -f "$temp_conf_file"; return 1; }
    fi
    
    # 3. 运行Certbot进行验证
    # 3. 运行Certbot进行验证，并在执行前确保目录存在
    local certbot_cmd="$COMPOSE_CMD run --rm --entrypoint \"/bin/sh -c 'mkdir -p /var/www/certbot && certbot certonly --webroot -w /var/www/certbot --non-interactive --agree-tos -m $email -d $domain'\" certbot"
    
    local success=0
    if eval $certbot_cmd; then
        log_info "证书申请成功: $domain"
        success=0
    else
        log_error "证书申请失败: $domain"
        log_error "请检查: 1. 域名解析是否正确指向本机IP. 2. 防火墙是否开放80端口."
        success=1
    fi

    # 4. 清理临时配置文件
    log_info "清理临时验证配置..."
    rm -f "$temp_conf_file"
    
    return $success
}

# 显示已安装的证书
show_certificates() {
    log_info "正在查询已安装的证书..."
    cd "$NGINX_DIR"
    $COMPOSE_CMD run --rm certbot certificates
}