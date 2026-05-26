# 运维 Runbook

本 runbook 面向 demo/PoC 环境。它帮助判断容器内各服务是否正常，不替代生产级监控、备份和告警。

## 健康检查

```bash
# 无鉴权 — Nginx 自身
curl http://localhost:7860/nginx-health

# 无鉴权 — 综合健康
curl http://localhost:7860/healthz

# 需 OPS_TOKEN — 详细健康
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/health
```

`/healthz` 和 `/_ops/healthz` 都会检查 MySQL、Redis 和 NocoDB。任一后端失败时返回 `503`。

## 获取 OPS_TOKEN

推荐在 HF Space Secrets 或本地 `docker run -e OPS_TOKEN=...` 中显式设置。

如果本地 demo 使用自动生成的 token，且使用默认 volume `db-hfs-persist`，可读取 `/data/config/generated.env`：

```bash
docker run --rm --entrypoint bash \
  -v db-hfs-persist:/data \
  db-all-in-one-hfs:latest \
  -lc 'grep "^_GEN_OPS_TOKEN=" /data/config/generated.env'
```

远程 HF Space 如果没有显式设置 `OPS_TOKEN`，自动生成的 token 不会通过公开接口返回；这时建议在 Space Secrets 中设置固定 `OPS_TOKEN` 后重启。

## 查看进程状态

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/status
```

## 查看日志

```bash
# NocoDB 日志（最后 200 行）
curl -H "X-Ops-Token: $OPS_TOKEN" "http://localhost:7860/_ops/logs?service=nocodb&lines=200"

# MySQL 错误日志
curl -H "X-Ops-Token: $OPS_TOKEN" "http://localhost:7860/_ops/logs?service=mysql.error&lines=100"

# 可用 service:
# supervisord, mysql, mysql.err, mysql.error, mysql.slow, redis, nocodb, nocodb.err, nginx
```

`lines` 最大按 `1000` 处理。`nginx` 对应 `/data/logs/nginx.log`，主要是 Nginx stdout/access log；Nginx error log 写到 stderr。

## 查看安全配置快照

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/config
```

该接口只返回白名单键，不返回 MySQL 密码、JWT secret 或 `OPS_TOKEN`。

## 常见问题排查

### 502 Bad Gateway

排查顺序：
1. `/nginx-health` → Nginx 是否存活
2. `/healthz` → 哪个后端服务不健康
3. `/_ops/status` → supervisor 进程状态
4. `/_ops/logs?service=nocodb.err` → NocoDB 错误日志

### MySQL 无法启动

检查：
- `/data/mysql` 目录权限
- `/_ops/logs?service=mysql.error` → 错误详情
- 磁盘空间是否充足
- 如果复用旧 `/data`，确认当前 `MYSQL_ROOT_PASSWORD` 与已初始化数据目录一致

### NocoDB 无法连接 MySQL

检查：
- MySQL 是否运行（`/_ops/status`）
- Socket 文件是否存在：`/data/run/mysqld/mysqld.sock`
- `/_ops/config` 中的 `MYSQL_DATABASE`、`MYSQL_USER`、`PORT`
- `/data/config/supervisor.env` 中的 `NC_DB` 是否指向 `127.0.0.1:3306`

### 首次启动超时

MySQL 初始化（`--initialize-insecure`）在首次运行需要额外时间。HEALTHCHECK 的 `start-period=90s` 已预留缓冲。如果硬件较慢，可增加到 120s。

### 修改端口后启动失败

入口脚本会校验 `PORT=8080` 和 `OPS_PORT=8081`，因为 Nginx、Supervisor 和 healthcheck 都使用固定内部路由。不要只通过环境变量改端口；需要同步修改 runtime 配置和文档。

## 进入容器调试

```bash
docker exec -it db-aio-hfs-demo bash

# 检查 MySQL
. /data/config/generated.env
mysqladmin -u root -p"$_GEN_MYSQL_ROOT_PASSWORD" --socket=/data/run/mysqld/mysqld.sock status

# 检查 Redis
redis-cli -p 6379 ping

# 检查 supervisor
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf status
```

如果容器由后台示例启动，容器名是 `db-aio-hfs`；如果由 `scripts/run-demo.sh` 启动，默认容器名是 `db-aio-hfs-demo`。

## 备份

```bash
docker exec db-aio-hfs bash -lc '
  . /data/config/generated.env
  mysqldump --socket=/data/run/mysqld/mysqld.sock \
    -u root -p"$_GEN_MYSQL_ROOT_PASSWORD" \
    --all-databases
' > backup.sql
```

本仓库不提供自动恢复、定时备份或异地备份。生产数据请迁移到独立 MySQL 服务。
