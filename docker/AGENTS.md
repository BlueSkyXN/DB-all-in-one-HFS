# docker/ navigation card

`docker/` 是容器 runtime 的高风险配置区，控制 entrypoint、进程编排、端口路由、持久化目录、secret 生成和只读诊断面。
修改本目录任意文件前先读本卡片；重点文件是 `entrypoint.sh`、`supervisord.conf`、`nginx.conf`、`ops_service.py`、`healthcheck.sh`、`my.cnf`。
本目录规则优先于根 `AGENTS.md` 中对 runtime 的概述。

## 为什么高风险

- 一个文件改错可能导致 Hugging Face Space 无法启动、healthcheck 失败或 NocoDB 不可访问。
- `/data/config/generated.env` 保存自动生成的 secret；任何日志、config endpoint 或文档样例都不能泄露原文。
- `/_ops` 是公开入口下的诊断路径，只能提供只读能力。
- `/data/run/db-aio-public` 是允许 Nginx 公开服务的 wrapper 静态文件目录；不要把公开静态文件放进 `/data/config`。
- MySQL、Redis、NocoDB、ops-service 都应只在容器内通过 `127.0.0.1` 通信。

## 修改前检查

- 改端口或路由前，对齐 `nginx.conf`、`supervisord.conf`、`entrypoint.sh`、`healthcheck.sh`、根 `Dockerfile`、`README.md`。
- 改 env var 前，对齐 `entrypoint.sh`、`supervisord.conf`、`ops_service.py`、`docs/configuration.md`。
- 改 NocoDB UI 默认语言初始化前，对齐 `entrypoint.sh` 的 `NC_DEFAULT_LOCALE` 校验和 JS 生成、`nginx.conf` 的 exact static route 与 HTML 注入、`ops_service.py` safe keys、README 和 docs。
- 改 `nginx.conf` 的 `location /` 时注意 `proxy_set_header` 继承规则：只要 location 内新增任意 `proxy_set_header`，就必须显式保留需要的 proxy headers。
- 新增服务前，对齐 `supervisord.conf`、`healthcheck.sh`、`ops_service.py` 的 `SERVICE_LOGS` 和 Nginx 路由。
- 改 MySQL 路径前，保持 socket 语义一致：`/data/run/mysqld/mysqld.sock`。

## 本地不变量

- `entrypoint.sh` 和 `healthcheck.sh` 使用 Bash，并保持 `set -euo pipefail`。
- `ops_service.py` 只使用 Python 标准库，不新增第三方依赖。
- Nginx 对外监听 `7860`；NocoDB 内部为 `8080`；ops-service 内部为 `8081`。
- Nginx 只用 exact path 暴露 `/__db_aio/nocodb-locale-init.js`；不要新增目录级 alias 暴露 `/data/config` 或整个 `/data/run`。
- Nginx 只对 exact `/signup` 和 `/signup/` 做兼容重定向到 `/signin/`；不要把 `/signup/<token>` 这类潜在 token 路径通配改写掉。
- `location /` 的 NocoDB HTML 注入依赖 `sub_filter` 和关闭 upstream `Accept-Encoding`；修改后必须做 Nginx 语法和模块验证。
- `ops_service.py` 的 `/config` 只能返回 safe keys，不能返回 password、token、JWT secret 或完整环境变量。
- `my.cnf` 不应把 MySQL 绑定到公网地址。

## Do not

- 不要在 `/_ops` 下新增写操作、SQL 执行、服务重启、文件删除或 secret 轮换接口。
- 不要把 MySQL、Redis、NocoDB 内部端口直接暴露给 Space 公网入口。
- 不要把 `/data/config`、`generated.env`、`supervisor.env` 或 secret-adjacent 目录通过 Nginx alias 暴露。
- 不要把 `NC_DEFAULT_LOCALE` 作为 NocoDB 官方环境变量描述；它是 wrapper 层的 localStorage 初始化逻辑。
- 不要把 generated secret、`OPS_TOKEN`、MySQL password 或 JWT secret 写入日志、响应、文档样例或测试快照。
- 不要静默升级 MySQL/NocoDB 大版本或更改 `/data` 持久化边界。

## Validation

- `bash -n docker/entrypoint.sh docker/healthcheck.sh`
- `python3 -m py_compile docker/ops_service.py`
- `scripts/static-check.sh`
- `docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -V 2>&1 | grep http_sub_module`
- `docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -t -c /etc/nginx/nginx.conf`

Docker 行为验证需要 Docker daemon 和网络：`scripts/build.sh`、`scripts/run-demo.sh`、`scripts/smoke.sh http://localhost:7860`。
