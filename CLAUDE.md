# DB-all-in-one-HFS 开发指南

## 项目概述

MySQL 9.7 LTS + NocoDB 一体化容器，部署于 Hugging Face Spaces。

## 构建与运行

```bash
# 构建镜像
docker build -t db-all-in-one-hfs .

# 本地运行
docker run --rm -p 7860:7860 -v db_data:/data db-all-in-one-hfs

# 仅构建检查（不运行）
docker build --target builder -t db-hfs-check . 2>&1 | tail -5
```

## 架构

- `Dockerfile` — 基于 Ubuntu 24.04，安装 MySQL 9.7 + Node.js + NocoDB
- `start.sh` — 进程管理脚本，启动 MySQL 和 NocoDB，监控进程健康
- `my.cnf` — MySQL 配置（字符集、性能调优、日志）
- `README.md` — 用户文档

## 关键约定

1. 单容器多服务使用 `tini` 作为 init 进程
2. 所有持久化数据统一放在 `/data` 下
3. 端口 7860（HF Spaces 规范）
4. 环境变量控制所有配置，不硬编码
5. MySQL 仅监听 127.0.0.1，不对外暴露
6. start.sh 负责进程生命周期管理和优雅退出
