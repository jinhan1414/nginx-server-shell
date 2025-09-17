#!/bin/bash

# 运行设置向导
run_setup_wizard() {
    log_info "首次运行或修改配置，启动设置向导..."
    
    echo "请选择SSL模式:"
    echo "1. Let's Encrypt (推荐, 自动申请和续订SSL证书)"
    echo "2. Cloudflare (适用于通过Cloudflare处理SSL的场景)"
    echo "3. 禁用SSL (不加密，不推荐)"
    read -p "请输入选择 [1-3]: " ssl_choice

    local temp_ssl_mode=""
    local temp_email=""
    local temp_cf_acl=""

    case $ssl_choice in
        1)
            temp_ssl_mode="letsencrypt"
            read -p "请输入您的邮箱地址 (用于Let's Encrypt续订提醒): " temp_email
            while [[ -z "$temp_email" ]]; do
                read -p "邮箱不能为空，请重新输入: " temp_email
            done
            ;;
        2)
            temp_ssl_mode="cloudflare"
            read -p "是否开启Cloudflare IP访问限制? (y/N): " cf_confirm
            if [[ "$cf_confirm" =~ ^[Yy]$ ]]; then
                temp_cf_acl="true"
            else
                temp_cf_acl="false"
            fi
            ;;
        3)
            temp_ssl_mode="disabled"
            ;;
        *)
            log_error "无效选择，退出。"
            exit 1
            ;;
    esac

    # 写入配置文件
    cat > "$CONFIG_FILE" << EOF
# Nginx 部署脚本配置文件
SSL_MODE="$temp_ssl_mode"
LETSENCRYPT_EMAIL="$temp_email"
CLOUDFLARE_IP_ACL="$temp_cf_acl"
EOF
    log_info "配置已保存到 $CONFIG_FILE"
}

# 加载或创建配置
load_or_create_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        run_setup_wizard
    fi
    
    # 加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "已加载配置: SSL_MODE=$SSL_MODE"
    else
        exit_on_error "配置文件 $CONFIG_FILE 不存在，无法继续。"
    fi
}