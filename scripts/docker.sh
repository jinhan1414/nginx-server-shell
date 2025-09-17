#!/bin/bash

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

# 创建Docker/Podman Compose文件
create_compose_file() {
    log_info "生成Docker Compose文件..."
    
    local podman_opts=""
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        podman_opts=",Z"
    fi

    cat > "$NGINX_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "8080:8080"
EOF

    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        echo '      - "443:443"' >> "$NGINX_DIR/docker-compose.yml"
    fi

    cat >> "$NGINX_DIR/docker-compose.yml" << EOF
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro${podman_opts}
      - ./conf.d:/etc/nginx/conf.d:rw${podman_opts}
      - ./data/nginx-logs:/var/log/nginx${podman_opts}
EOF

    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        cat >> "$NGINX_DIR/docker-compose.yml" << EOF
      - ./data/certbot/certs:/etc/letsencrypt:ro${podman_opts}
      - ./data/certbot/www:/var/www/certbot:rw${podman_opts}
EOF
    fi

    cat >> "$NGINX_DIR/docker-compose.yml" << EOF
    networks:
      - shared-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        cat >> "$NGINX_DIR/docker-compose.yml" << EOF

  certbot:
    image: certbot/certbot:latest
    container_name: certbot-service
    volumes:
      - ./data/certbot/certs:/etc/letsencrypt${podman_opts}
      - ./data/certbot/www:/var/www/certbot${podman_opts}
    # 使用 command 使其成为一个常驻服务，以兼容 podman-compose run
    # 并定期执行续订检查
    command: |
      /bin/sh -c 'trap exit TERM; while :; do certbot renew --quiet; sleep 12h & wait $${!}; done;'
EOF
    fi

    cat >> "$NGINX_DIR/docker-compose.yml" << EOF

networks:
  shared-network:
    external: true
EOF
    log_info "Docker Compose文件生成完成"
}