# 运维 Runbook

## 健康检查

```bash
# 无鉴权 — Nginx 自身
curl http://localhost:7860/nginx-health

# 无鉴权 — 综合健康
curl http://localhost:7860/healthz

# 需 OPS_TOKEN — 详细健康
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/health
```

## 查看进程状态

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/status
```

## 查看日志

```bash
# NocoDB 日志（最后 200 行）
curl -H "X-Ops-Token: $OPS_TOKEN" "http://localhost:7860/_ops/logs?service=nocodb&lines=200"

# MySQL 错误日志
curl -H "X-Ops-Token: $OPS_TOKEN" "http://localhost:7860/_ops/logs?service=mysql.err&lines=100"

# 可用 service: supervisord, mysql, mysql.err, redis, nocodb, nocodb.err, nginx
```

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
- `/_ops/logs?service=mysql.err` → 错误详情
- 磁盘空间是否充足

### NocoDB 无法连接 MySQL

检查：
- MySQL 是否运行（`/_ops/status`）
- Socket 文件是否存在：`/data/run/mysqld/mysqld.sock`
- NocoDB 环境变量 `NC_DB` 是否正确

### 首次启动超时

MySQL 初始化（`--initialize-insecure`）在首次运行需要额外时间。HEALTHCHECK 的 `start-period=90s` 已预留缓冲。如果硬件较慢，可增加到 120s。

## 进入容器调试

```bash
docker exec -it db-aio-hfs bash

# 检查 MySQL
mysqladmin -u root -p"$MYSQL_ROOT_PASSWORD" --socket=/data/run/mysqld/mysqld.sock status

# 检查 Redis
redis-cli -p 6379 ping

# 检查 supervisor
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf status
```
