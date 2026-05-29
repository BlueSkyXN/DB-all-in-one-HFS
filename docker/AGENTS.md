# docker/ navigation card

`docker/` 负责容器启动、进程编排、Nginx 路由、持久化目录、generated secrets 和只读 ops 诊断面。
修改 `entrypoint.sh`、`supervisord.conf`、`nginx.conf`、`ops_service.py`、`healthcheck.sh` 或 `my.cnf` 前先读本卡片。
本卡片的 runtime 细节优先于根 `AGENTS.md` 的概述。

## Guardrails / 边界

- HF public entry 保持 Nginx `7860`；内部路由保持 NocoDB `8080`、ops-service `8081`、MySQL socket `/data/run/mysqld/mysqld.sock`。
- `/data` 是持久化边界。不要通过 Nginx 暴露 `/data/config`、`generated.env`、`supervisor.env` 或完整 `/data/run`。
- `/_ops` 只读：不要新增 SQL、restart、mutation、delete 或 secret rotation endpoint。
- `ops_service.py` 只使用 Python 标准库；`/config` 只能返回 safe keys，不能泄露 password、token、JWT secret 或 generated secret。
- Locale init 是 wrapper 能力：`NC_DEFAULT_LOCALE` -> generated JS -> exact `/__db_aio/nocodb-locale-init.js` -> `sub_filter`。不要描述成 NocoDB 官方 env var。
- `/signup` 和 `/signup/` 只做 exact redirect；不要通配重写 `/signup/<token>`。

## Before Changes / 修改前

- 改端口或路由：同步检查 `nginx.conf`、`supervisord.conf`、`entrypoint.sh`、`healthcheck.sh`、根 `Dockerfile` 和 `README.md`。
- 改 env var：同步检查 `entrypoint.sh`、`supervisord.conf`、`ops_service.py` 和 `docs/configuration.md`。
- 改 `location /`：如果新增任何 `proxy_set_header`，显式保留必要 proxy headers；HTML 注入仍需 `Accept-Encoding ""`。
- 新增服务：同步更新 `supervisord.conf`、`healthcheck.sh`、`ops_service.py` 的 `SERVICE_LOGS` 和 Nginx routing。
- Bash 脚本保持 `set -euo pipefail`；不要把 MySQL 绑定到 public address。

## Validation

- `bash -n docker/entrypoint.sh docker/healthcheck.sh`
- `python3 -m py_compile docker/ops_service.py`
- `scripts/static-check.sh`
- Docker-only: `scripts/build.sh`, Nginx `-V` / `-t`, `scripts/run-demo.sh`, `scripts/smoke.sh http://localhost:7860`.
