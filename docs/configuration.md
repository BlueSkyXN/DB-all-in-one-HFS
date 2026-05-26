# 配置参考

## 环境变量

### MySQL

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_ROOT_PASSWORD` | (自动生成) | MySQL root 密码 |
| `MYSQL_DATABASE` | `nocodb` | 默认数据库名 |
| `MYSQL_USER` | `nocodb` | NocoDB 使用的 MySQL 用户名 |
| `MYSQL_PASSWORD` | (自动生成) | NocoDB 使用的 MySQL 密码 |

### NocoDB

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NC_AUTH_JWT_SECRET` | (自动生成) | JWT 签名密钥 |
| `NC_SITE_URL` | (空) | 公网访问 URL，设置后影响分享链接和邮件链接 |
| `NC_PUBLIC_URL` | (空) | 兼容旧变量；未设置 `NC_SITE_URL` 时会作为 fallback |
| `NC_DISABLE_TELE` | `true` | 禁用遥测数据收集 |

### Ops Service

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPS_TOKEN` | (自动生成) | 访问 `/_ops/` 的鉴权令牌 |
| `OPS_PORT` | `8081` | ops-service 内部监听端口；当前必须保持 `8081` |

### Redis

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REDIS_PORT` | `6379` | Redis 内部监听端口 |

### Build Args

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_VERSION` | `9.7` | Oracle MySQL APT channel |
| `NOCODB_VERSION` | `0.301.3` | 构建时安装的 NocoDB npm 版本 |

### 通用

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DATA_DIR` | `/data` | 持久化数据根目录 |

## 内部端口约束

HF Docker Space 对外入口固定为 Nginx `7860`。当前 `nginx.conf` 对 NocoDB 和 ops-service 使用固定内部路由：

| 服务 | 内部端口 |
|------|---------:|
| NocoDB | `8080` |
| ops-service | `8081` |
| MySQL | `3306` |
| Redis | `6379` |

不要只通过环境变量修改 `PORT`、`NC_PORT` 或 `OPS_PORT`。如确实需要改内部端口，必须同步修改 `docker/nginx.conf`、`docker/supervisord.conf`、`docker/entrypoint.sh`、`docker/healthcheck.sh` 和相关文档。

## Secret 管理

首次启动时，如果未通过环境变量提供密钥，`entrypoint.sh` 会自动生成并持久化到 `/data/config/generated.env`。后续重启会加载已生成的值。

优先级（高到低）：
1. Docker/HF 注入的环境变量
2. `/data/config/generated.env` 中已生成的值
3. 自动随机生成新值

## Ops Endpoints

| 路径 | 鉴权 | 说明 |
|------|------|------|
| `/_ops/healthz` | 无 | 综合健康检查（MySQL + Redis + NocoDB） |
| `/_ops/health` | OPS_TOKEN | 同 healthz，带鉴权 |
| `/_ops/status` | OPS_TOKEN | Supervisor 进程状态 |
| `/_ops/logs?service=X&lines=N` | OPS_TOKEN | 查看服务日志尾部 |
| `/_ops/config` | OPS_TOKEN | 查看安全配置项（不含 secret） |

鉴权方式：
- Header: `X-Ops-Token: <token>`
- Query: `?token=<token>`
