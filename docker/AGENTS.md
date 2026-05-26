# docker/ 目录 Agent 指令

## 职责

本目录包含 Docker runtime 的所有配置和脚本：

| File | Role |
| --- | --- |
| `entrypoint.sh` | 容器启动入口：secret 生成、MySQL 初始化、启动 supervisord |
| `supervisord.conf` | 进程管理：MySQL、Redis、NocoDB、ops-service、Nginx |
| `nginx.conf` | 反向代理：端口 7860 对外，路由到内部服务 |
| `my.cnf` | MySQL 配置（字符集、性能、日志） |
| `healthcheck.sh` | Docker HEALTHCHECK 脚本 |
| `ops_service.py` | 只读诊断 HTTP 服务（Python 标准库） |

## 修改规则

- 修改 `entrypoint.sh` 后必须 `bash -n docker/entrypoint.sh`
- 修改 `ops_service.py` 后必须 `python3 -m py_compile docker/ops_service.py`
- 修改端口/路由必须同步 `nginx.conf`、`supervisord.conf`、`entrypoint.sh`
- 新增服务必须同步 `supervisord.conf`、`healthcheck.sh`、`ops_service.py` 的 SERVICE_LOGS
- `ops_service.py` 不引入第三方依赖，仅用 Python 标准库
- MySQL socket 路径统一为 `/data/run/mysqld/mysqld.sock`
