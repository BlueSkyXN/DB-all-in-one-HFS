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

面向 **Hugging Face Docker Space** 的 MySQL 9.7 LTS + NocoDB 单容器 Demo 工程。它把 NocoDB、MySQL、Redis、Nginx 和一个只读 `ops-service` 收敛到同一个容器中，用于数据库可视化管理和轻量 PoC。

> 该工程不是生产部署方案。生产环境应使用独立的 MySQL 服务，并补齐高可用、备份、鉴权、监控、容量规划和正式运维流程。

## HFS v3.0 Preview 定位

本仓库是 **Pattern A / HFS Port Repository**：仓库根目录是 GitHub 维护根和 Space wrapper root，而不是产品源码镜像。NocoDB runtime 走 **artifact** 车道：

`hfs-dev.toml` 将项目登记为 `project_class="preview"`、canonical target `target_role="primary"`。Preview 可直接修改 canonical Space 并在写后 readback；任何 Secret 都必须先保存在 ignored plaintext `.env`。`hfs-dev.candidate.toml` 只用于高风险可选验证，独立账本为 `local/hfs-targets/candidate.env`。

1. 受确认的发布工作流从 `Dockerfile` 的 `NOCODB_SOURCE_REF`（tag + digest）导出 rootfs archive；tag 发布进入 GitHub Release，`edge`/`release` slot 保留当前 archive。
2. 上传 archive 后必须读回并核验 SHA-256，最后才写 slot 的 `manifest.json`。
3. Space 启动仅读取 `NOCODB_ARTIFACT_MANIFEST_URL` 指定的一个 manifest，校验 slot、上游 ref、wrapper commit、文件名、大小、SHA-256 和 rootfs 布局，再下载并解包到容器本地运行目录。
4. 缺 manifest、URL、slot、archive、校验、平台或布局时直接非零退出；不会扫描目录、改用旧 rootfs 或回退至 OCI build-stage runtime。

`/data` 仍只存 NocoDB 普通文件、配置、日志和 MySQL 逻辑备份。MySQL (`/home/user/mysql`)、Redis (`/home/user/redis`) 和下载的 NocoDB runtime (`/home/user/run/nocodb-runtime`) 均留在容器本地；不要把 MySQL 或 Redis datadir 放到 `/data` 的 FUSE bucket mount。

## 文档入口

- [架构说明](./docs/architecture.md)
- [配置参考](./docs/configuration.md)
- [部署指南](./docs/deployment.md)
- [开发指南](./docs/development.md)
- [运维 Runbook](./docs/ops-runbook.md)

## 组件布局

容器运行用户为 UID `1000`。`tini` 作为 PID 1，入口脚本先完成 fail-closed runtime bootstrap，再交给 `supervisord` 管理进程；Nginx 监听 HF Space 需要的 `7860`：

```text
nginx:7860
  ├─ NocoDB:8080
  ├─ ops-service:8081
  ├─ MySQL 9.7 LTS:3306
  └─ Redis:6379
```

- 只有 Nginx `7860` 对外；MySQL、Redis、NocoDB 和 `ops-service` 只绑定 `127.0.0.1`。
- `ops-service` 只读；认证后 `/_ops/provenance` 返回已验证 artifact 的无密身份信息。
- `/data` 持久化普通文件和逻辑备份；MySQL 的跨重启恢复从 `/data/backups` 的最新可读 dump 开始，损坏最新 dump 会尝试较早版本。

## 本地构建和运行

构建只生成基础设施 wrapper 镜像，不下载或嵌入 NocoDB 产品 runtime：

```bash
scripts/static-check.sh
scripts/build.sh

# 显式选择已发布的 manifest 和 slot；run-demo 保留 db-hfs-persist，
# 但会替换同名容器。
NOCODB_ARTIFACT_MANIFEST_URL='https://<approved-dist-host>/db-all-in-one-hfs/release/manifest.json' \
NOCODB_ARTIFACT_SLOT='release' \
NOCODB_ARTIFACT_DOWNLOAD_TOKEN='<private-bucket-read-token>' \
scripts/run-demo.sh

scripts/smoke.sh http://localhost:7860
```

不要把真实 URL 中的 credential、Space Secret 或 `/data` 内容写入仓库、日志或文档。`NOCODB_ARTIFACT_MANIFEST_URL` 必须是无凭据 HTTPS URL；本地 `.env` 使用 `.env.example` 作为无值键名模板且受 `.gitignore` 保护。

## Space Settings

在候选或已获批准的 Space 设置以下**键名**：

- Variables：`NC_SITE_URL`、`NC_DEFAULT_LOCALE`、`NOCODB_ARTIFACT_MANIFEST_URL`、`NOCODB_ARTIFACT_SLOT`（只允许 `edge` 或 `release`）。
- Secrets：`NOCODB_ARTIFACT_DOWNLOAD_TOKEN`、`MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD`、`NC_AUTH_JWT_SECRET`、`OPS_TOKEN`。

`HF_TOKEN` 和 `GH_TOKEN` 是本地/CI 控制面凭据，只登记在 `hfs-dev.toml` 的 `local_only`，绝不推送到 Space Settings。

## 发布和回退边界

`publish-nocodb-artifact.yml` 与 `deploy-hf-space.yml` 都只能手动触发，且需要输入精确确认字符串。它们不会 force-push、删除 bucket/Space/Settings、重启 Space、迁移数据库或恢复数据；所有远端写入后必须读回指定对象。运行前还需由 release owner、data owner 确认当前 Space ref、实际 `/data` mount、artifact 下载面、备份/RPO 和候选验证窗口。

历史 archive 的回退从 GitHub Release 的同一字节资产重新发布为 slot manifest；不得通过重置 `/data`、删除备份或直接修改运行中数据库实现回退。

## 许可证

GPL-3.0 — 详见 [LICENSE](./LICENSE)
