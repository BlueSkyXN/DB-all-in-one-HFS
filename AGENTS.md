# 仓库 Agent 指令

## 项目目的

`DB-all-in-one-HFS` 是面向 Hugging Face Docker Space 的 MySQL 9.7 LTS + NocoDB 单容器 Demo 工程。它把 MySQL、NocoDB、Redis、Nginx 和只读 `ops-service` 收敛到一个容器中，用于数据库可视化管理的演示和 PoC。

本仓库不是生产部署方案。生产环境应使用独立的 MySQL 服务和正式的高可用、备份、鉴权和监控。

## 目录地图

| Path | Responsibility | Local AGENTS.md |
| --- | --- | ---: |
| `README.md` | HF Space card、项目介绍 | No |
| `Dockerfile` | Docker Space 构建入口 | No |
| `.dockerignore` | Build context 过滤 | No |
| `docker/` | runtime: entrypoint、env、Supervisor、Nginx、MySQL、ops-service、healthcheck | Yes |
| `scripts/` | 本地 build/run/smoke 脚本 | No |
| `docs/` | 工程文档 | No |

## 真实命令面

| Command | Purpose |
| --- | --- |
| `scripts/static-check.sh` | Shell/Python 语法检查 |
| `scripts/build.sh` | 构建 Docker 镜像 |
| `scripts/run-demo.sh` | 本地启动 demo |
| `scripts/smoke.sh [url]` | Smoke 测试 |
| `bash -n docker/entrypoint.sh docker/healthcheck.sh` | Shell 语法验证 |
| `python3 -m py_compile docker/ops_service.py` | Python 语法验证 |

## 全局规则

- 始终把本仓库定位为 demo/all-in-one deployment bundle，不要写成生产级部署。
- 保持 HF Docker Space 约束：单容器、Nginx 监听 `7860`、UID 1000 运行、持久化数据在 `/data`。
- `README.md` 的 `app_port: 7860`、`docker/nginx.conf` 的 `listen 7860`、`Dockerfile EXPOSE 7860` 必须一致。
- `/data` 是 runtime persistence 边界。MySQL 数据、Redis、NocoDB 元数据、日志、generated secrets 都在此。
- entrypoint 生成的 secrets 属于 `/data/config/generated.env`；不要提交真实 secret。
- MySQL 仅绑定 `127.0.0.1`，内部端口不暴露到公网。
- `ops-service` 是只读诊断面。`/_ops` 不能新增写操作。
- Shell 脚本保持 `set -euo pipefail`，修改后跑 `bash -n`。
- 新增/重命名 env var 时同步检查 `docker/entrypoint.sh`、`docker/supervisord.conf`、`docker/ops_service.py`、`docs/configuration.md`。

## 不要做

- 不要在用户没有明确要求时执行 `git push`。
- 不要把 MySQL、Redis 内部端口暴露到 Space 公网入口。
- 不要在 `/_ops` 下新增写操作。
- 不要通过 ops config/logs 暴露 secret 原文。
- 不要静默升级 MySQL 或 NocoDB 大版本。

## 验证标准

Shell/Python 改动：

```bash
bash -n docker/entrypoint.sh docker/healthcheck.sh scripts/build.sh scripts/run-demo.sh scripts/smoke.sh scripts/static-check.sh
python3 -m py_compile docker/ops_service.py
git diff --check
```

如果 Docker 可用：

```bash
scripts/build.sh
scripts/run-demo.sh
scripts/smoke.sh http://localhost:7860
```
