#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    log_info "root用户运行"
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