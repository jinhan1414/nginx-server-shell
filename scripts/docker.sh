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
      - ./conf.d:/etc/nginx/conf.d:ro${podman_opts}
      - ./data/nginx-logs:/var/log/nginx${podman_opts}
EOF

    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        cat >> "$NGINX_DIR/docker-compose.yml" << EOF
      - ./data/certbot/certs:/etc/letsencrypt:ro${podman_opts}
      - ./data/certbot/www:/var/www/certbot${podman_opts}
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
    # Certbot 容器只在需要时通过 'run' 启动，不作为常驻服务
    # 定期续订将通过一个独立的 cron 任务或 systemd timer 实现
    command: sleep infinity
EOF
    fi

    cat >> "$NGINX_DIR/docker-compose.yml" << EOF

networks:
  shared-network:
    external: true
EOF
    log_info "Docker Compose文件生成完成"
}