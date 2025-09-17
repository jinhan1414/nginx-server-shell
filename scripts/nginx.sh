#!/bin/bash

# 获取Cloudflare IP列表
update_cf_ips() {
    log_info "获取Cloudflare IP列表..."
    
    if ! curl -s --connect-timeout 5 https://www.cloudflare.com &> /dev/null; then
        exit_on_error "无法连接到Cloudflare，请检查网络连接"
    fi
    
    CF_IPS_V4=$(curl -s --connect-timeout 10 --max-time 20 https://www.cloudflare.com/ips-v4)
    if [[ $? -ne 0 || -z "$CF_IPS_V4" ]]; then
        exit_on_error "获取Cloudflare IPv4列表失败"
    fi
    
    CF_IPS_V6=$(curl -s --connect-timeout 10 --max-time 20 https://www.cloudflare.com/ips-v6)
    if [[ $? -ne 0 || -z "$CF_IPS_V6" ]]; then
        exit_on_error "获取Cloudflare IPv6列表失败"
    fi
    
    if ! echo "$CF_IPS_V4" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' &> /dev/null; then
        exit_on_error "获取到的Cloudflare IPv4列表格式不正确"
    fi
    
    log_info "成功获取Cloudflare IP列表"
}

# 生成Nginx基础配置
generate_base_config() {
    log_info "生成Nginx配置文件..."
    
    cat > "$NGINX_DIR/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    '"$host" "$http_cf_ray"';
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF

    if [[ "$SSL_MODE" == "cloudflare" && "$CLOUDFLARE_IP_ACL" == "true" ]]; then
        update_cf_ips
        echo "    # Cloudflare真实IP设置" >> "$NGINX_DIR/nginx.conf"
        echo "$CF_IPS_V4" | while IFS= read -r ip; do if [[ ! -z "$ip" ]]; then echo "    set_real_ip_from $ip;" >> "$NGINX_DIR/nginx.conf"; fi; done
        echo "$CF_IPS_V6" | while IFS= read -r ip; do if [[ ! -z "$ip" ]]; then echo "    set_real_ip_from $ip;" >> "$NGINX_DIR/nginx.conf"; fi; done
        echo "    real_ip_header CF-Connecting-IP;" >> "$NGINX_DIR/nginx.conf"
    fi

    if [[ "$SSL_MODE" != "letsencrypt" ]]; then
        cat >> "$NGINX_DIR/nginx.conf" << 'EOF'
    server {
        listen 80 default_server;
        server_name _;
        access_log /var/log/nginx/blocked.log main;
        return 444;
    }
EOF
    else
        # 在 Let's Encrypt 模式下，acme-challenge 的处理逻辑将直接注入到服务配置中
        # 这里只需要一个最终的捕获所有请求的服务器
        cat >> "$NGINX_DIR/nginx.conf" << 'EOF'
    server {
        listen 80 default_server;
        server_name _;
        access_log /var/log/nginx/blocked.log main;
        return 444;
    }
EOF
    fi

    cat >> "$NGINX_DIR/nginx.conf" << 'EOF'
    server {
        listen 8080;
        server_name localhost;
        location /health {
            access_log off;
            return 200 "nginx healthy\n";
            add_header Content-Type text/plain;
        }
    }
    include /etc/nginx/conf.d/*.conf;
}
EOF
    log_info "Nginx配置文件生成完成"
}

# 添加新的后端服务
add_backend_service() {
    log_question "请输入要添加的服务信息："
    read -p "子域名 (如: gpt-load): " subdomain
    read -p "主域名 (如: xxx.xyz): " domain
    read -p "后端容器名 (如: gpt-load-app): " container_name
    read -p "后端端口 (如: 3001): " port
    
    if [[ -z "$subdomain" || -z "$domain" || -z "$container_name" || -z "$port" ]]; then
        log_error "所有字段都必须填写"; return 1;
    fi
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "端口必须是1-65535之间的数字"; return 1;
    fi
    
    FULL_DOMAIN="$subdomain.$domain"
    CONFIG_FILE="$NGINX_DIR/conf.d/$subdomain.conf"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        read -p "配置文件已存在，是否覆盖? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "取消添加服务"; return 0; fi
    fi

    case "$SSL_MODE" in
        "letsencrypt")
            if ! request_certificate "$FULL_DOMAIN" "$LETSENCRYPT_EMAIL"; then return 1; fi
            log_info "生成Let's Encrypt模式的配置文件: $CONFIG_FILE"
            cat > "$CONFIG_FILE" << EOF
# $FULL_DOMAIN (Let's Encrypt)
upstream ${subdomain}-backend { server ${container_name}:${port}; }
server {
    listen 80; server_name ${FULL_DOMAIN};

    # 优先处理 Let's Encrypt 的 HTTP-01 验证
    # 优先处理 Let's Encrypt 的 HTTP-01 验证
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl http2; server_name ${FULL_DOMAIN};
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
            ;;
        "cloudflare")
            log_info "生成Cloudflare模式的配置文件: $CONFIG_FILE"
            cat > "$CONFIG_FILE" << EOF
# $FULL_DOMAIN (Cloudflare)
upstream ${subdomain}-backend { server ${container_name}:${port}; }
server {
    listen 80; server_name ${FULL_DOMAIN};
EOF
            if [[ "$CLOUDFLARE_IP_ACL" == "true" ]]; then
                cat >> "$CONFIG_FILE" << 'EOF'
    if (\$http_cf_connecting_ip = "") { return 403; }
EOF
            fi
            cat >> "$CONFIG_FILE" << EOF
    access_log /var/log/nginx/${subdomain}_access.log main;
    error_log /var/log/nginx/${subdomain}_error.log;
    location / {
        proxy_pass http://${subdomain}-backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_cf_visitor_scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_set_header CF-RAY \$http_cf_ray;
        proxy_set_header CF-Visitor \$http_cf_visitor;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
            ;;
        "disabled")
            log_info "生成禁用SSL模式的配置文件: $CONFIG_FILE"
            cat > "$CONFIG_FILE" << EOF
# $FULL_DOMAIN (Disabled SSL)
upstream ${subdomain}-backend { server ${container_name}:${port}; }
server {
    listen 80; server_name ${FULL_DOMAIN};
    access_log /var/log/nginx/${subdomain}_access.log main;
    error_log /var/log/nginx/${subdomain}_error.log;
    location / {
        proxy_pass http://${subdomain}-backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
            ;;
    esac

    log_info "已创建配置文件: $FULL_DOMAIN -> $container_name:$port"
    
    if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t; then
        if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -s reload; then
            log_info "Nginx配置已成功重载"
        else
            log_error "Nginx重载失败"
        fi
    else
        log_error "Nginx配置测试失败"
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
        log_info "正在重载Nginx..."
        if $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -t && $CONTAINER_ENGINE exec $CONTAINER_NAME nginx -s reload; then
            log_info "Nginx已重载。"
        else
            log_error "Nginx重载失败，请检查配置。"
        fi
    else
        log_info "取消删除操作"
    fi
}