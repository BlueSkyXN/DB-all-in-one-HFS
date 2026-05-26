---
title: DB-all-in-one-HFS
emoji: 🗄️
colorFrom: blue
colorTo: purple
sdk: docker
app_port: 7860
pinned: false
---

# DB-all-in-one-HFS

面向 **Hugging Face Docker Space** 的 MySQL 9.7 LTS + NocoDB 单容器 Demo 工程。

NocoDB 提供类 Airtable 的可视化数据库管理界面，底层使用 MySQL 9.7 LTS 作为持久化存储。

> 该工程不是生产部署方案。生产环境应使用独立的 MySQL 服务和适当的高可用设计。

## 文档入口

- [架构说明](./docs/architecture.md)
- [配置参考](./docs/configuration.md)
- [部署指南](./docs/deployment.md)
- [开发指南](./docs/development.md)
- [运维 Runbook](./docs/ops-runbook.md)

## 组件布局

容器内由 `supervisord` 启动多个进程，Nginx 在端口 `7860` 反向代理：

```text
nginx:7860
  ├─ NocoDB:8080
  ├─ ops-service:8081
  ├─ MySQL 9.7 LTS:3306
  └─ Redis:6379
```

关键设计：

- MySQL 仅绑定 `127.0.0.1`，不暴露到公网
- NocoDB 使用 Redis 作为缓存层
- `ops-service` 提供只读诊断面（`/_ops/`）
- 运行时采用 UID `1000` 非 root 用户
- 所有密钥首次启动自动生成，持久化到 `/data/config/`

## 本地运行

```bash
# 构建
scripts/build.sh

# 运行
scripts/run-demo.sh

# Smoke 测试
scripts/smoke.sh http://localhost:7860
```

启动后访问：

- NocoDB UI: `http://localhost:7860`
- 健康检查: `http://localhost:7860/healthz`
- Ops 诊断: `http://localhost:7860/_ops/health`（需 OPS_TOKEN）

## Hugging Face Space 部署

1. 新建 Space，SDK 选择 **Docker**。
2. 推送本仓库文件到 Space 根目录。
3. 在 Space Settings → Secrets 设置：
   - `MYSQL_ROOT_PASSWORD`（可选，不设则自动生成）
   - `MYSQL_PASSWORD`（可选，不设则自动生成）
   - `NC_AUTH_JWT_SECRET`（可选，不设则自动生成）
   - `OPS_TOKEN`（推荐设置，用于 `/_ops/` 鉴权）

## 许可证

GPL-3.0 — 详见 [LICENSE](./LICENSE)
