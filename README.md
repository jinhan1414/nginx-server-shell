# Nginx反向代理部署脚本

## 功能特性

- 🚀 **一键部署**：自动部署和配置Nginx反向代理
- 🐳 **多容器引擎支持**：自动检测并支持Docker和Podman
- ☁️ **Cloudflare集成**：通过Cloudflare CDN访问内网服务
- 🔒 **安全防护**：防止IP直接访问，只允许通过域名访问
- 🎯 **简单管理**：交互式菜单管理后端服务
- 📊 **实时监控**：内置健康检查和日志查看

## 系统要求

### 必需软件
- **容器引擎**：Docker 或 Podman
- **编排工具**：docker-compose 或 podman-compose
- **网络工具**：curl
- **系统**：Linux (推荐CentOS/Ubuntu/Debian)

### 安装依赖

#### CentOS/RHEL/Fedora (Podman)
```bash
# 安装Podman和相关工具
sudo dnf install podman podman-compose curl

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
sudo apt update && sudo apt install curl
```

## 快速开始

### 1. 下载脚本
```bash
# 创建工作目录
mkdir -p /your-services/nginx
cd /your-services/nginx

# 下载脚本 (替换为实际下载链接)
wget https://your-domain/nginx-deploy.sh
# 或者直接创建文件并复制脚本内容

# 赋予执行权限
chmod +x nginx-deploy.sh
```

### 2. 运行脚本
```bash
./nginx-deploy.sh
```

### 3. 首次运行
脚本会自动：
- 检测容器引擎
- 获取Cloudflare IP列表
- 生成Nginx配置
- 创建Docker网络
- 启动Nginx容器

## 详细使用教程

### 步骤1：准备域名和DNS

1. **购买域名**（如：xxx.xyz）
2. **添加到Cloudflare**：
   - 登录Cloudflare控制台
   - 添加站点：xxx.xyz
   - 按照提示修改域名DNS服务器

### 步骤2：配置Cloudflare

1. **SSL/TLS设置**：
   - 进入 SSL/TLS 页面
   - 加密模式选择：**Flexible** 或 **Full**
   - 开启"始终使用HTTPS"

2. **DNS记录准备**（稍后添加）：
   ```
   类型: A
   名称: gpt-load  (子域名)
   内容: 你的服务器IP
   代理状态: 已代理（橙色云朵图标）
   ```

### 步骤3：准备后端服务

在运行nginx脚本之前，确保你的后端服务已经部署。

**示例：部署一个简单的后端服务**
```bash
# 创建后端服务目录
mkdir -p /your-services/gpt-load
cd /your-services/gpt-load

# 创建docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  gpt-load-app:
    image: your-app-image:latest  # 替换为你的镜像
    container_name: gpt-load-app
    expose:
      - "3001"
    networks:
      - shared-network
    restart: unless-stopped
    environment:
      - NODE_ENV=production

networks:
  shared-network:
    external: true
EOF

# 启动后端服务
podman-compose up -d  # 或 docker-compose up -d
```

### 步骤4：使用Nginx脚本添加服务

1. **运行脚本**：
   ```bash
   cd /your-services/nginx
   ./nginx-deploy.sh
   ```

2. **选择菜单选项1**："添加后端服务"

3. **输入服务信息**：
   ```
   子域名: gpt-load
   主域名: xxx.xyz
   后端容器名: gpt-load-app
   后端端口: 3001
   ```

4. **脚本会自动**：
   - 生成Nginx配置
   - 测试配置文件
   - 重载Nginx
   - 提示你添加DNS记录

### 步骤5：添加DNS记录

在Cloudflare控制台添加DNS记录：
- **类型**：A
- **名称**：gpt-load
- **内容**：你的服务器公网IP
- **代理状态**：开启（橙色云朵）

### 步骤6：测试访问

等待DNS传播（通常几分钟），然后访问：
```
https://gpt-load.xxx.xyz
```

## 脚本功能详解

### 主菜单功能

```
1. 添加后端服务    - 添加新的反向代理配置
2. 列出现有服务    - 查看所有已配置的服务
3. 删除服务       - 删除指定的服务配置
4. 重启Nginx      - 重启Nginx容器
5. 查看日志       - 查看访问日志/错误日志/容器日志
6. 更新Cloudflare IP - 更新CF IP列表并重启
7. 测试配置       - 测试Nginx配置语法
8. 查看容器状态    - 查看容器和网络状态
0. 退出           - 退出脚本
```

### 目录结构
运行后会生成以下目录结构：
```
/your-services/nginx/
├── nginx-deploy.sh      # 主脚本
├── nginx.conf           # 主配置文件
├── docker-compose.yml   # 容器编排文件
└── conf.d/             # 服务配置目录
    └── gpt-load.conf   # 具体服务配置
```

## 常见问题

### Q1: 脚本运行失败，提示网络错误？
**A**: 检查服务器是否能访问互联网：
```bash
curl -I https://www.cloudflare.com
```

### Q2: 容器启动失败？
**A**: 检查端口是否被占用：
```bash
# 检查80端口
sudo netstat -tulnp | grep :80

# 或使用ss命令
ss -tulnp | grep :80
```

### Q3: 域名无法访问？
**A**: 按顺序检查：
1. DNS记录是否正确添加
2. Cloudflare代理是否开启（橙色云朵）
3. 服务器防火墙是否允许80端口
4. 后端服务是否正常运行

### Q4: 如何查看详细错误？
**A**: 查看各种日志：
```bash
# 容器日志
./nginx-deploy.sh  # 选择菜单5 -> 3

# Nginx错误日志
./nginx-deploy.sh  # 选择菜单5 -> 2

# 查看容器状态
./nginx-deploy.sh  # 选择菜单8
```

### Q5: 如何添加多个服务？
**A**: 重复运行脚本，选择菜单1，每次添加一个服务。每个服务使用不同的子域名。

## 高级配置

### 自定义Nginx配置

如果需要自定义配置，可以直接编辑生成的配置文件：
```bash
# 编辑主配置
vim /your-services/nginx/nginx.conf

# 编辑特定服务配置
vim /your-services/nginx/conf.d/gpt-load.conf

# 测试配置
./nginx-deploy.sh  # 选择菜单7

# 重启应用配置
./nginx-deploy.sh  # 选择菜单4
```

### 添加SSL证书

脚本默认通过Cloudflare处理SSL，无需在服务器配置证书。如需自定义证书，请修改配置文件。

### 防火墙配置

推荐只允许Cloudflare IP访问：
```bash
# 使用UFW的示例
sudo ufw allow ssh
sudo ufw allow from 173.245.48.0/20 to any port 80
sudo ufw enable
```

## 安全建议

1. **定期更新**：定期运行菜单选项6更新Cloudflare IP
2. **监控日志**：定期查看访问日志，发现异常访问
3. **备份配置**：定期备份nginx配置目录
4. **最小权限**：不要使用root用户运行脚本

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
