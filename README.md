# Nginx反向代理部署脚本

## 功能特性

- 🚀 **一键部署**：自动部署和配置Nginx反向代理
- 🔒 **自动化SSL**：内置 Let's Encrypt 支持，自动申请和续订免费SSL证书
- 强制HTTPS：自动将HTTP请求重定向到HTTPS
-  **多容器引擎支持**：自动检测并支持Docker和Podman
- ☁️ **灵活的Cloudflare集成**：可选择通过Cloudflare CDN访问，并可选择是否开启IP访问限制
- 模式切换：支持 **Let's Encrypt**、**Cloudflare** 和 **无SSL** 三种工作模式
- 🎯 **简单管理**：交互式菜单管理后端服务
- 📊 **实时监控**：内置健康检查和日志查看

## 系统要求

### 必需软件
- **容器引擎**：Docker 或 Podman
- **编排工具**：docker-compose 或 podman-compose
- **网络工具**：curl, openssl (用于生成自签名证书以供首次启动)
- **系统**：Linux (推荐CentOS/Ubuntu/Debian)

### 安装依赖

#### CentOS/RHEL/Fedora (Podman)
```bash
# 安装Podman和相关工具
sudo dnf install podman podman-compose curl openssl

# 或使用pip安装podman-compose
pip3 install podman-compose
```

#### Ubuntu/Debian (Docker)
```bash
# 安装Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 安装curl
sudo apt update && sudo apt install curl openssl
```

## 快速开始

### 1. 下载脚本
```bash
# 创建工作目录
mkdir -p /your-services/nginx
cd /your-services/nginx
# 直接下载并执行
curl -fsSL https://raw.githubusercontent.com/jinhan1414/nginx-server-shell/main/nginx-deploy.sh | bash
# 下载脚本 (替换为实际下载链接)
curl -fsSL https://raw.githubusercontent.com/jinhan1414/nginx-server-shell/main/nginx-deploy.sh -o nginx-deploy.sh

# 或者直接创建文件并复制脚本内容

# 赋予执行权限
chmod +x nginx-deploy.sh
```

### 2. 运行脚本
```bash
./nginx-deploy.sh
```

### 3. 首次运行：设置向导
首次运行脚本时，会进入一个交互式设置向导：
1.  **选择SSL模式**:
    *   **Let's Encrypt (推荐)**: 自动申请和管理免费SSL证书。
    *   **Cloudflare**: 适用于将SSL交给Cloudflare处理的场景。
    *   **禁用SSL**: 不使用加密（不推荐）。
2.  **输入配置**:
    *   如果选择 Let's Encrypt，需要提供一个邮箱地址。
    *   如果选择 Cloudflare，可以选择是否开启IP访问限制。

配置将保存在 `config.sh` 文件中，方便后续修改。

### 4. 脚本自动完成初始化
- 检测容器引擎和依赖
- 根据你的选择生成 `docker-compose.yml` 和 `nginx.conf`
- 创建共享网络
- 启动 Nginx 容器 (以及 Certbot 容器，如果需要)

## 详细使用教程

### 步骤1：准备域名和DNS

**重要**: 无论使用何种模式，你都需要一个域名，并将其 **A记录** 指向你的服务器公网IP。

- **对于 Let's Encrypt 模式**: 确保域名解析已生效，因为 Let's Encrypt 服务器需要通过域名访问你的服务器来完成验证。**不要开启 Cloudflare 的代理（橙色云朵）**，至少在首次申请证书时不要开启。
- **对于 Cloudflare 模式**: DNS记录的配置方式与之前相同，建议开启代理（橙色云朵）。

### 步骤2 (可选): 配置Cloudflare

如果你使用 **Cloudflare 模式**，请在 Cloudflare 控制台进行相应设置，例如 SSL/TLS 加密模式选择 `Flexible` 或 `Full`。

### 步骤3：准备后端服务

在运行nginx脚本之前，确保你的后端服务已经部署在同一个容器网络 (`shared-network`) 中。

(后端服务部署示例保持不变...)

### 步骤4：使用Nginx脚本添加服务

1.  **运行脚本**：
    ```bash
    cd /your-services/nginx
    ./nginx-deploy.sh
    ```

2.  **选择菜单选项1**："添加后端服务"

3.  **输入服务信息** (与之前相同)。

4.  **脚本会自动处理**:
   - **Let's Encrypt 模式**:
     - 自动为你的域名申请SSL证书。
     - 生成监听443端口的HTTPS配置和80端口的HTTP重定向配置。
     - 重载Nginx。
   - **Cloudflare / 禁用SSL 模式**:
     - 生成监听80端口的HTTP配置。
     - 重载Nginx。

### 步骤5：测试访问

等待DNS传播后，即可访问你的服务。
```
# Let's Encrypt 模式下，会自动跳转到 https
http://gpt-load.xxx.xyz
```

## 脚本功能详解

### 主菜单功能

```
1. 添加后端服务
2. 列出现有服务
3. 删除服务
4. 重启Nginx及所有服务
5. 查看日志
6. 手动续订所有SSL证书 (仅Let's Encrypt模式)
7. 修改脚本配置
8. 测试Nginx配置
9. 查看容器状态
0. 退出
```

### 目录结构
```
/your-services/nginx/
├── nginx-deploy.sh      # 主脚本
├── config.sh            # (新) 配置文件
├── nginx.conf           # 主配置文件
├── docker-compose.yml   # 容器编排文件
└── conf.d/             # 服务配置目录
└── data/                # (新) 持久化数据目录
    ├── certbot/
    │   ├── www/
    │   └── certs/
    └── nginx-logs/
```

## 常见问题

(保留原有Q&A，并增加新的)
### Q: Let's Encrypt 证书申请失败怎么办？
**A**: 最常见的原因是DNS记录未生效或防火墙拦截。
1. 确保你的域名A记录已正确指向服务器IP。可以使用 `ping your-domain.com` 来检查。
2. 确保你的服务器防火墙已开放 80 和 443 端口。
3. 检查 Certbot 容器日志：`./nginx-deploy.sh` -> 菜单 5 -> 3. 容器日志 -> 选择 certbot。

## 高级配置与模式切换

你可以随时通过运行 `./nginx-deploy.sh` 并选择菜单 "7. 修改脚本配置" 来更改 SSL 模式或相关配置。注意，切换模式后，可能需要重启 Nginx 服务来使所有更改生效。

### 防火墙配置
```bash
# UFW 示例 (Let's Encrypt 模式)
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 安全建议

1. **监控日志**：定期查看访问日志，发现异常访问
2. **备份配置**：定期备份nginx配置目录
3. **最小权限**：不要使用root用户运行脚本

## 故障排除

### 完全重置
如果遇到无法解决的问题，可以完全重置：
```bash
# 停止并删除容器
podman-compose down  # 或 docker-compose down
podman container rm nginx-proxy  # 或 docker container rm nginx-proxy

# 删除配置文件
rm -rf conf.d/
rm nginx.conf docker-compose.yml

# 重新运行脚本
./nginx-deploy.sh
```

### 查看系统资源
```bash
# 查看容器资源使用
podman stats  # 或 docker stats

# 查看系统资源
htop
df -h
```

## 许可证

本脚本基于MIT许可证开源，可自由使用和修改。

## 贡献

欢迎提交Issue和Pull Request改进此脚本！

---

**需要帮助？** 请检查上述常见问题部分，或提交Issue描述具体问题。
