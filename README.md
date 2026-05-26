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

它把 NocoDB、MySQL、Redis、Nginx 和一个只读 `ops-service` 收敛到同一个容器中，用于在 HF Space 上演示数据库可视化管理和轻量 PoC。

> 该工程不是生产部署方案。生产环境应使用独立的 MySQL 服务，并补齐高可用、备份、鉴权、监控和容量规划。

## 文档入口

- [架构说明](./docs/architecture.md)
- [配置参考](./docs/configuration.md)
- [部署指南](./docs/deployment.md)
- [开发指南](./docs/development.md)
- [运维 Runbook](./docs/ops-runbook.md)

## 组件布局

容器运行用户为 UID `1000`。`tini` 作为 PID 1，入口脚本完成初始化后交给 `supervisord` 管理进程，Nginx 监听 HF Space 需要的 `7860`：

```text
nginx:7860
  ├─ NocoDB:8080
  ├─ ops-service:8081
  ├─ MySQL 9.7 LTS:3306
  └─ Redis:6379
```

关键设计：

- 只有 Nginx `7860` 对外；MySQL、Redis、NocoDB 和 `ops-service` 只绑定 `127.0.0.1`
- NocoDB 使用 MySQL 作为业务数据库，使用 Redis 作为缓存层
- `ops-service` 提供只读诊断面，外部路径为 `/_ops/`
- `/data` 是唯一持久化边界，包含数据库、日志、Redis 快照和生成的配置
- 首次启动自动生成缺省 secret，并持久化到 `/data/config/generated.env`

## 本地运行

```bash
# 构建默认镜像 db-all-in-one-hfs:latest
scripts/build.sh

# 使用 named volume db-hfs-persist 运行 demo
scripts/run-demo.sh

# 检查公开健康端点和 NocoDB 首页
scripts/smoke.sh http://localhost:7860
```

启动后访问：

- NocoDB UI: <http://localhost:7860/>
- Nginx 健康检查: <http://localhost:7860/nginx-health>
- 综合健康检查: <http://localhost:7860/healthz>
- Ops 诊断: <http://localhost:7860/_ops/health>（需 `OPS_TOKEN`）

如果需要远程或本地稳定访问 `/_ops/`，建议显式设置 `OPS_TOKEN`。不设置时入口脚本会生成 token，但该 token 只保存在 `/data/config/generated.env`，不会通过公开接口返回。

## Hugging Face Space 部署

1. 新建 Space，SDK 选择 **Docker**。
2. 推送本仓库文件到 Space 根目录。
3. 建议启用 Persistent Storage，否则重建后 `/data` 中的 MySQL 数据和生成 secret 会丢失。
4. 在 Space Settings -> Variables 设置：
   - `NC_SITE_URL`（可选，设置为 Space 公网 URL 时可改善分享链接）
5. 在 Space Settings -> Secrets 设置：
   - `MYSQL_ROOT_PASSWORD`（可选，不设则自动生成）
   - `MYSQL_PASSWORD`（可选，不设则自动生成）
   - `NC_AUTH_JWT_SECRET`（可选，不设则自动生成）
   - `OPS_TOKEN`（推荐设置，用于 `/_ops/` 鉴权）

不要把真实 secret 提交到 Git。更多配置项见 [配置参考](./docs/configuration.md)。

## 许可证

GPL-3.0 — 详见 [LICENSE](./LICENSE)
