# Nginx反向代理部署脚本

## 功能
- 自动部署Nginx反向代理
- 支持Docker和Podman
- 通过Cloudflare CDN访问内网服务
- 防止IP直接访问
- 简单的Web界面管理后端服务

## 使用方法
1. 确保安装了Docker/Podman和对应的compose工具
2. 运行脚本：`./nginx-deploy.sh`
3. 首次运行会自动初始化Nginx
4. 通过菜单添加后端服务

## 要求
- Docker + docker-compose 或 Podman + podman-compose
- curl命令
- 服务器需要能访问互联网（获取Cloudflare IP列表）

## 注意事项
- 确保在Cloudflare中正确配置DNS记录
- 建议使用非root用户运行
