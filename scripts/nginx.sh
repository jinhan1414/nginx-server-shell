#!/bin/bash

# 添加新的后端服务
add_backend_service() {
    log_question "请输入要添加的服务信息："
    read -p "您的邮箱地址 (用于Let's Encrypt提醒): " email
    read -p "子域名 (如: gpt-load): " subdomain
    read -p "主域名 (如: xxx.xyz): " domain
    read -p "后端服务地址 (如: 192.168.1.97:3001): " backend_address
    
    if [[ -z "$email" || -z "$subdomain" || -z "$domain" || -z "$backend_address" ]]; then
        log_error "所有字段都必须填写"; return 1;
    fi
    
    FULL_DOMAIN="$subdomain.$domain"
    CONFIG_FILE="$NGINX_DIR/conf.d/$subdomain.conf"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        read -p "配置文件已存在，是否覆盖? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "取消添加服务"; return 0; fi
    fi

    if ! request_certificate "$FULL_DOMAIN" "$email"; then return 1; fi
    
    log_info "生成最终的Nginx配置文件: $CONFIG_FILE"
    
    cat > "$CONFIG_FILE" << EOF
# $FULL_DOMAIN
upstream ${subdomain}-backend {
    server ${backend_address};
}

server {
    listen 80;
    server_name ${FULL_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${FULL_DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${FULL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FULL_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    access_log /var/log/nginx/${subdomain}_access.log main;
    error_log /var/log/nginx/${subdomain}_error.log;

    location / {
        proxy_pass http://${subdomain}-backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    log_info "已创建配置文件: $FULL_DOMAIN -> $backend_address"
    
    if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t; then
        log_info "Nginx配置测试通过，正在重启以应用最终配置..."
        cd "$NGINX_DIR"
        if $COMPOSE_CMD restart nginx; then
            log_info "Nginx已成功重启"
        else
            log_error "Nginx重启失败"
        fi
    else
        log_error "最终生成的Nginx配置测试失败，请检查。"
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
    read -p "请输入要删除的服务名称 (不含.conf): " service_name
    
    if [[ -z "$service_name" ]]; then log_error "服务名称不能为空"; return 1; fi
    
    CONFIG_FILE="$NGINX_DIR/conf.d/$service_name.conf"
    if [[ ! -f "$CONFIG_FILE" ]]; then log_error "配置文件不存在: $CONFIG_FILE"; return 1; fi
    
    read -p "确认删除服务 $service_name? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        log_info "服务 $service_name 的配置文件已删除。"
        log_info "正在重启Nginx以应用更改..."
        cd "$NGINX_DIR"
        if $COMPOSE_CMD restart nginx; then
            log_info "Nginx已重启。"
        else
            log_error "Nginx重启失败，请检查配置。"
        fi
    else
        log_info "取消删除操作"
    fi
}