# 运维 Runbook

本 runbook 面向 demo/PoC 运行态，不替代生产监控、数据库 HA、PITR、异地备份或正式 incident process。不得用以下命令读取、打印或上传 `generated.env`、`supervisor.env`、Secret、数据库内容或真实 dump。

## 健康与 provenance

```bash
curl http://localhost:7860/nginx-health
curl http://localhost:7860/healthz
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/health
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/provenance
```

`/healthz` 同时检查 MySQL、Redis 和 NocoDB。认证后的 `/_ops/provenance` 用于核对已验证的 artifact `source_ref`、wrapper SHA、slot、archive name/SHA-256、生成时间；它不会返回 artifact URL、Settings、token、密码或完整环境。使用之前应在受保护 shell 中获取 `OPS_TOKEN`，不要将值放进日志或文档。

## 进程、日志和安全配置

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/status
curl -H "X-Ops-Token: $OPS_TOKEN" "http://localhost:7860/_ops/logs?service=nocodb.err&lines=100"
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/config
```

可用日志 service：`supervisord`、`mysql`、`mysql.err`、`mysql.error`、`mysql.slow`、`mysql.backup`、`mysql.backup.err`、`redis`、`nocodb`、`nocodb.err`、`nginx`。日志面会 best-effort 脱敏，但仍按敏感诊断材料处理。`/_ops/config` 只含 allowlisted 非敏感配置；不要扩展为写操作、SQL、重启、secret 输出或环境 dump。

## Artifact bootstrap failure

manifest/bootstrap 失败时容器在 MySQL 初始化和 `/data` 写入前退出。排查只限无密元数据：

1. 确认 Space Variable `NOCODB_ARTIFACT_MANIFEST_URL` 是无凭据 HTTPS manifest URL，`NOCODB_ARTIFACT_SLOT` 为 `edge` 或 `release`，并且 Space Secret `NOCODB_ARTIFACT_DOWNLOAD_TOKEN` 已登记；Secret 只核名称，不打印值。
2. 在发布 receipt 中核对 slot manifest 的 `source_ref` 是否等于 Dockerfile `NOCODB_SOURCE_REF`、`wrapper_source_ref` 是否完整 40 位、archive name/size/SHA-256 是否 readback 成功。
3. 确认 artifact URL 的 basename 与 manifest archive name 相同，archive 的 rootfs 含当前架构 musl loader、Node 和 `usr/src/app/docker/index.js`。
4. 不要以 direct archive、`latest`、目录列举、旧 `/home/user/run/nocodb-runtime` 或 Dockerfile OCI COPY 作为临时 fallback。修复明确 manifest/artifact 后重新启动即可。

Space 显示 RUNNING 不能替代 `/healthz`、`/_ops/provenance`、NocoDB UI/API、MySQL/Redis/Nginx 和持久化验收。

## 备份与恢复

- `mysql-backup` 将逻辑 dump 写到 `/data/backups/nocodb-*.sql.gz`，每个 dump 用 `gzip -t` 检查，优雅停机时会再尝试一次。
- 启动恢复按文件名从新到旧尝试；损坏或上传不完整的最新 dump 不会阻止尝试较早 dump。
- `/data/backups/.keep` 是 FUSE mount 的目录 marker，不要删除。
- MySQL datadir `/home/user/mysql`、Redis `/home/user/redis`、socket/pid/runtime `/home/user/run` 必须保持容器本地；在 `/data` 上放 InnoDB/RDB 可能触发 rename/redo 失败。

任何真实 backup、restore、restart/rebuild、mount 改动或 retention cleanup 都需要 data owner 的独立授权。先在隔离 bucket/prefix 和候选 Space 执行：创建一个无敏感验证对象、受控备份、校验 gzip、故意跳过损坏副本的恢复验证、NocoDB 登录/API readback、重启后再读回。不得在本 demo 以外声称该流程满足生产 RPO/RTO。

## 常见问题

### 502 / public 失败

依次检查 `/nginx-health`、`/healthz`、认证 `/_ops/status`、`/_ops/logs?service=nocodb.err`。若 NocoDB 未启动，优先检查 bootstrap receipt，而不是暴露内部端口或修改 MySQL/Redis 公网绑定。

### MySQL 启动失败

确认 datadir 未迁入 `/data`，检查 `mysql.error` 日志和 Space 磁盘容量。不要读取或复制 `/data/config/generated.env`。MySQL 9.7 `TempTable` 可能出现无 error code 的 `mbind: Operation not permitted`；结合 health/status 与相邻 MySQL error code 判断，不要仅凭该单行认定故障。

### locale 未生效

确认 `NC_DEFAULT_LOCALE` 是 `en`、`zh-Hans` 或 `zh-Hant`；检查 `/signup` 重定向、`/__db_aio/nocodb-locale-init.js` 和浏览器 localStorage。该变量只是 wrapper 初始化行为，不是 NocoDB 官方 locale 配置。
