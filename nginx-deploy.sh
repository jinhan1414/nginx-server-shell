#!/bin/bash

# 设置脚本目录为工作目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# --- 全局变量 ---
NGINX_DIR="$SCRIPT_DIR"
NETWORK_NAME="shared-network"
CONTAINER_NAME="nginx-proxy"

# 容器引擎变量
CONTAINER_ENGINE=""
COMPOSE_CMD=""

# --- 加载模块 ---
source "scripts/common.sh"
source "scripts/certbot.sh"
source "scripts/nginx.sh"
source "scripts/menu.sh"

# --- 主程序入口 ---
run_main_loop "$@"
