#!/bin/bash

# 运行设置向导
run_setup_wizard() {
    log_info "首次运行，将默认使用 Let's Encrypt 模式。"
    
    local temp_ssl_mode="letsencrypt"
    local temp_email=""
    local temp_cf_acl=""

    read -p "请输入您的邮箱地址 (用于Let's Encrypt续订提醒): " temp_email
    while [[ -z "$temp_email" ]]; do
        read -p "邮箱不能为空，请重新输入: " temp_email
    done

    # 写入配置文件
    cat > "$CONFIG_FILE" << EOF
# Nginx 部署脚本配置文件
SSL_MODE="$temp_ssl_mode"
LETSENCRYPT_EMAIL="$temp_email"
CLOUDFLARE_IP_ACL="$temp_cf_acl"
EOF
    log_info "配置已保存到 $CONFIG_FILE"
}

# 修改SSL模式
change_ssl_mode() {
    log_info "修改SSL模式..."
    
    echo "请选择新的SSL模式:"
    echo "1. Let's Encrypt (推荐)"
    echo "2. Cloudflare"
    echo "3. 禁用SSL"
    read -p "请输入选择 [1-3]: " ssl_choice

    local temp_ssl_mode=""
    local temp_email="$LETSENCRYPT_EMAIL" # 保留旧邮箱
    local temp_cf_acl="$CLOUDFLARE_IP_ACL"

    case $ssl_choice in
        1)
            temp_ssl_mode="letsencrypt"
            read -p "请输入您的邮箱地址 (当前: $temp_email): " new_email
            if [[ ! -z "$new_email" ]]; then temp_email="$new_email"; fi
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
            log_error "无效选择，操作取消。"
            return 1
            ;;
    esac

    cat > "$CONFIG_FILE" << EOF
# Nginx 部署脚本配置文件
SSL_MODE="$temp_ssl_mode"
LETSENCRYPT_EMAIL="$temp_email"
CLOUDFLARE_IP_ACL="$temp_cf_acl"
EOF
    log_info "配置已更新。请重启服务以应用更改。"
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