# 配置参考

本仓库的配置分为三类：

- HF/Docker 注入的运行时环境变量
- 入口脚本首次启动时生成并写入 `/data/config/generated.env` 的 secret
- Docker build arg

除 `NC_SITE_URL`、`NC_DEFAULT_LOCALE` 这类公开配置外，secret 应放在 HF Space Settings -> Secrets 或本地 `docker run -e` 中，不要提交到 Git。

## 环境变量

### MySQL

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_ROOT_PASSWORD` | (自动生成) | MySQL root 密码 |
| `MYSQL_DATABASE` | `nocodb` | 默认数据库名 |
| `MYSQL_USER` | `nocodb` | NocoDB 使用的 MySQL 用户名 |
| `MYSQL_PASSWORD` | (自动生成) | NocoDB 使用的 MySQL 密码 |

`MYSQL_DATABASE` 和 `MYSQL_USER` 只能包含字母、数字和下划线。复用已有 `/data/mysql` 时，`MYSQL_ROOT_PASSWORD` 必须与已初始化数据目录中的 root 密码一致，否则启动阶段无法重新配置用户。

### NocoDB

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NC_AUTH_JWT_SECRET` | (自动生成) | JWT 签名密钥 |
| `NC_SITE_URL` | (空) | 公网访问 URL，设置后影响分享链接和邮件链接 |
| `NC_PUBLIC_URL` | (空) | 兼容旧变量；未设置 `NC_SITE_URL` 时会作为 fallback |
| `NC_DISABLE_TELE` | `true` | 禁用遥测数据收集 |
| `NC_DEFAULT_LOCALE` | `zh-Hans` | 初始化 NocoDB UI 默认语言；支持 `en`、`zh-Hans`、`zh-Hant`。该变量通过 wrapper 注入脚本初始化浏览器 localStorage，不是 NocoDB 官方环境变量 |
| `NC_PORT` | `8080` | NocoDB 内部端口来源；当前必须保持 `8080` |
| `PORT` | `NC_PORT` | NocoDB 实际监听端口；入口脚本校验必须为 `8080` |

入口脚本会生成：

```text
NC_DB=mysql2://127.0.0.1:3306?u=<MYSQL_USER>&p=<MYSQL_PASSWORD>&d=<MYSQL_DATABASE>
NC_APP_DATA_DIR=/data/nocodb
NC_TOOL_DIR=/data/nocodb
NC_CACHE_REDIS_URL=redis://127.0.0.1:6379
NC_REDIS_URL=redis://127.0.0.1:6379
```

这些派生变量不建议手工覆盖。要修改数据库名、用户名、密码或 Redis 端口，应改上表对应的源变量，并确认内部端口约束。

### Ops Service

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPS_TOKEN` | (自动生成) | 访问 `/_ops/` 的鉴权令牌 |
| `OPS_PORT` | `8081` | ops-service 内部监听端口；当前必须保持 `8081` |

`OPS_TOKEN` 未显式设置时会自动生成，并写入 `/data/config/generated.env`。远程 HF Space 上如果需要稳定调用 `/_ops/status`、`/_ops/logs` 或 `/_ops/config`，建议在 Space Secrets 中显式设置它。

### Redis

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REDIS_PORT` | `6379` | Redis 内部监听端口 |

`REDIS_PORT` 会写入 `/data/run/redis.conf`，同时用于 NocoDB 的 Redis URL 和 ops-service 的 Redis health check。Nginx 不代理 Redis。

### Build Args

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBUNTU_VERSION` | `24.04@sha256:4fbb…` | Ubuntu 24.04 LTS 基础镜像 tag + OCI index digest |
| `MYSQL_VERSION` | `9.7` | Oracle MySQL APT channel |
| `MYSQL_SERVER_PACKAGE` | `mysql-server=9.7.1-1ubuntu24.04` | MySQL 9.7.1 LTS server package spec |
| `MYSQL_CLIENT_PACKAGE` | `mysql-client=9.7.1-1ubuntu24.04` | 与 server 对齐的 MySQL client package spec |
| `NOCODB_IMAGE_REF` | `nocodb/nocodb:2026.07.0@sha256:fb359…` | 官方 NocoDB multi-arch OCI image，必须同时包含 release tag 和 digest |

当前默认 build args 已全部 immutable pin。上游更新时应先核对官方 release、APT metadata 和 OCI digest，再成组更新版本与 digest。NocoDB `2026.06.1` 之后不再发布 standalone executable，因此 `NOCODB_IMAGE_REF` 是唯一受支持的 NocoDB build source。

### 通用

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DATA_DIR` | `/data` | 固定持久化数据根目录；入口脚本会拒绝其他值 |

## 内部端口约束

HF Docker Space 对外入口固定为 Nginx `7860`。当前 `nginx.conf` 对 NocoDB 和 ops-service 使用固定内部路由：

| 服务 | 内部端口 |
|------|---------:|
| NocoDB | `8080` |
| ops-service | `8081` |
| MySQL | `3306` |
| Redis | `6379` |

不要只通过环境变量修改 `PORT`、`NC_PORT`、`OPS_PORT` 或 `DATA_DIR`。如确实需要改内部端口或持久化根目录，必须同步修改 `docker/nginx.conf`、`docker/supervisord.conf`、`docker/entrypoint.sh`、`docker/healthcheck.sh`、`docker/my.cnf`、脚本和相关文档。

## Secret 管理

首次启动时，如果未通过环境变量提供密钥，`entrypoint.sh` 会自动生成并持久化到 `/data/config/generated.env`。后续重启会加载已生成的值。

优先级（高到低）：
1. Docker/HF 注入的环境变量
2. `/data/config/generated.env` 中已生成的值
3. 自动随机生成新值

`/data/config/generated.env` 使用 `_GEN_*` 变量保存最终 secret，包括：

| 变量 | 用途 |
| --- | --- |
| `_GEN_MYSQL_ROOT_PASSWORD` | MySQL root 密码 |
| `_GEN_MYSQL_PASSWORD` | NocoDB MySQL 用户密码 |
| `_GEN_NC_AUTH_JWT_SECRET` | NocoDB JWT secret |
| `_GEN_OPS_TOKEN` | ops-service token |

`/data/config/supervisor.env` 是诊断用环境快照，权限为 `600`。它也包含敏感值，不应复制到公开日志、issue、PR 或文档中。

## Ops Endpoints

| 路径 | 鉴权 | 说明 |
|------|------|------|
| `/healthz` | 无 | 通过 Nginx 代理到 ops-service `/healthz` |
| `/_ops/healthz` | 无 | 综合健康检查（MySQL + Redis + NocoDB） |
| `/_ops/` 或 `/_ops/health` | `OPS_TOKEN` | 综合健康检查，带鉴权 |
| `/_ops/status` | `OPS_TOKEN` | Supervisor 进程状态 |
| `/_ops/logs?service=X&lines=N` | `OPS_TOKEN` | 查看服务日志尾部；`lines` 最大按 `1000` 处理 |
| `/_ops/config` | `OPS_TOKEN` | 查看白名单配置项，不含 secret |

鉴权方式：
- Header: `X-Ops-Token: <token>`
- Query: `?token=<token>`

`/_ops/logs` 会对当前环境中已知 secret 做 best-effort 脱敏；但日志仍应按敏感诊断材料处理，不要复制到公开 issue、PR 或文档中。

可查询的日志 service 名称：

| service | 文件 |
| --- | --- |
| `supervisord` | `/data/logs/supervisord.log` |
| `mysql` | `/data/logs/mysql.log` |
| `mysql.err` | `/data/logs/mysql.err` |
| `mysql.error` | `/data/logs/mysql-error.log` |
| `mysql.slow` | `/data/logs/mysql-slow.log` |
| `redis` | `/data/logs/redis.log` |
| `nocodb` | `/data/logs/nocodb.log` |
| `nocodb.err` | `/data/logs/nocodb.err` |
| `nginx` | `/data/logs/nginx.log` |

`/_ops/config` 当前只返回这些键：`MYSQL_DATABASE`、`MYSQL_USER`、`PORT`、`NC_DISABLE_TELE`、`OPS_PORT`、`REDIS_PORT`、`DATA_DIR`、`MYSQL_VERSION`、`MYSQL_SERVER_PACKAGE`、`MYSQL_CLIENT_PACKAGE`、`UBUNTU_VERSION`、`NOCODB_IMAGE_REF`、`NC_SITE_URL`、`NC_DEFAULT_LOCALE`。
