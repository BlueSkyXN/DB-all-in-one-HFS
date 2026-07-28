# 配置参考

配置分为 Space runtime Settings、Docker build pins 与本地控制面账本。`hfs-dev.toml` 只登记键名和关系；真实值只能留在忽略的本地 `.env` 或 Space Secrets，绝不进入 manifest、archive、wrapper bundle、日志或文档。

## 本地账本

以 `.env.example` 创建受保护的 `.env`，再在适当的本地/CI 环境使用。模板只包含空键名：

- 本地控制面：`HF_TOKEN`、`GH_TOKEN`。二者不得成为 Space Secret/Variable。
- Space Secrets：`NOCODB_ARTIFACT_DOWNLOAD_TOKEN`、`MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD`、`NC_AUTH_JWT_SECRET`、`OPS_TOKEN`。
- Space Variables：`NC_SITE_URL`、`NC_DEFAULT_LOCALE`、`NOCODB_ARTIFACT_MANIFEST_URL`、`NOCODB_ARTIFACT_SLOT`。

`.gitignore` 与 `.dockerignore` 同时排除 `.env*`（保留 `.env.example`）、`local/`、缓存、runtime data、SQL dump、archive 和 key material。

## Artifact runtime

| Variable | 必需 | 约束 |
|---|---:|---|
| `NOCODB_ARTIFACT_MANIFEST_URL` | 是 | 无 credential/query 的 HTTPS `manifest.json` URL；启动仅读取一次 |
| `NOCODB_ARTIFACT_SLOT` | 是 | `edge` 或 `release`，必须与 manifest 完全相同 |
| `NOCODB_ARTIFACT_DOWNLOAD_TOKEN` | 是（Space Secret） | 私有 HFS bucket 的只读 token；只作为首跳 Bearer header 使用，不写入 URL、argv、manifest 或日志 |
| `NOCODB_SOURCE_REF` | 否（image build pin） | `Dockerfile` 内固定的 NocoDB tag + OCI digest；bootstrap 将其与 manifest `source_ref` 比对 |

`NOCODB_ARTIFACT_MANIFEST_URL` 不是 direct archive URL。manifest 必须声明 `schema_version=1`、项目、slot、`source_kind=oci-image`、tag+digest source ref、完整 wrapper commit、生成时间和一个 archive 的名称/HTTPS URL/SHA-256/size。任一字段不符合或 archive rootfs 不包含适配架构的 musl loader、Node、`docker/index.js` 时启动失败。

## MySQL

| Variable | 默认值 | 说明 |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | 自动生成 | MySQL root 密码 |
| `MYSQL_DATABASE` | `nocodb` | 默认数据库名，只能包含字母、数字、下划线 |
| `MYSQL_USER` | `nocodb` | NocoDB 用户，只能包含字母、数字、下划线 |
| `MYSQL_PASSWORD` | 自动生成 | NocoDB 用户密码 |
| `MYSQL_BACKUP_INTERVAL` | `300` | 逻辑备份间隔（秒） |
| `MYSQL_BACKUP_KEEP` | `6` | `/data/backups` 保留份数 |

MySQL datadir 固定为容器本地 `/home/user/mysql`。每次启动在本地初始化，然后从 `/data/backups` 的可读 `nocodb-*.sql.gz` 恢复。不要通过 `DATA_DIR` 或 mount 将该目录迁移到 `/data`。

## NocoDB、Ops 与 Redis

| Variable | 默认值 | 说明 |
|---|---|---|
| `NC_AUTH_JWT_SECRET` | 自动生成 | JWT secret |
| `NC_SITE_URL` | 空 | 公网 URL；未设置时兼容 `NC_PUBLIC_URL` |
| `NC_DISABLE_TELE` | `true` | 禁用遥测 |
| `NC_DEFAULT_LOCALE` | `zh-Hans` | wrapper 首次 UI locale；不是 NocoDB 官方 locale variable |
| `NC_PORT` / `PORT` | `8080` | 固定 NocoDB 内部端口 |
| `OPS_TOKEN` | 自动生成 | `/_ops/` token |
| `OPS_PORT` | `8081` | 固定 ops-service 内部端口 |
| `REDIS_PORT` | `6379` | 固定 Redis 内部端口 |
| `DATA_DIR` | `/data` | 固定 persistence root；其他值拒绝启动 |

入口脚本生成的 `NC_DB`、Redis URL 与 `/data/config/supervisor.env` 是派生/敏感运行配置，不应手动覆盖或导出。`generated.env`、`supervisor.env` 均属于私有状态，不能作为 artifact seed。

## Build pins

| Build arg | 规则 |
|---|---|
| `UBUNTU_VERSION` | Ubuntu tag + OCI digest |
| `MYSQL_VERSION` | Oracle MySQL APT channel |
| `MYSQL_SERVER_PACKAGE` / `MYSQL_CLIENT_PACKAGE` | 相同审计版本的精确 package spec |
| `NOCODB_SOURCE_REF` | 官方 NocoDB tag + OCI digest；artifact producer 的唯一上游输入 |
| `WRAPPER_SOURCE_REF` | 完整 Git SHA；`scripts/build.sh` 从 clean Git tree 推导，Space exporter 将同一 SHA 固化到导出的 Dockerfile，不能由 Space runtime Setting 覆盖 |

`scripts/build.sh` 接受上述 build args，并拒绝没有不可变 Git identity 的 dirty tree。`NOCODB_IMAGE_REF` 仅保留为本地调用方的兼容别名，并会映射为 `NOCODB_SOURCE_REF`；新调用应使用后者。更新 source ref 需要先重建 artifact、读回、生成 manifest-last、候选 Space smoke 与隔离恢复演练，不能只重建 wrapper。

## 只读 Ops endpoints

`/_ops/healthz` 和 `/healthz` 无需 token；其他 `/_ops` endpoint 需要 `OPS_TOKEN`。`/_ops/config` 只返回白名单非敏感键，`/_ops/provenance` 只返回经验证的 runtime identity，不返回 download URL、token、密码、JWT 或完整环境。
