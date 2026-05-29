# 仓库 Agent 指令

## 项目目的

`DB-all-in-one-HFS` 是面向 Hugging Face Docker Space 的 MySQL 9.7 LTS + NocoDB 单容器 Demo 工程。它把 MySQL、NocoDB、Redis、Nginx 和只读 `ops-service` 收敛到一个容器中，用于数据库可视化管理演示和轻量 PoC。

本仓库不是生产部署方案。不要把它描述、改造或包装成生产级数据库平台；生产环境应使用独立 MySQL 服务，并补齐高可用、备份、鉴权、监控、容量规划和正式运维流程。

## Codex 启动行为

- Codex 通常从仓库根目录启动；本文件是 repo-local 启动期主规则。
- 子目录 `AGENTS.md` 是按需导航卡片，不会在根启动 workflow 中自动进入上下文。
- 修改有本地 `AGENTS.md` 的目录前，必须先读取该目录的本地卡片。
- 如果未来新增更深层 `AGENTS.md`，修改目标文件前按从浅到深顺序读取路径链上的卡片。
- 子目录规则与本文件冲突时，以更接近目标文件的子目录规则为准。

## 目录地图

| Path | Responsibility | Local AGENTS.md | Read when |
| --- | --- | ---: | --- |
| `README.md` | Hugging Face Space card、项目介绍、本地运行和部署入口 | No | 修改项目定位、HF metadata、端口说明或公开文档入口时 |
| `Dockerfile` | Docker Space 镜像构建入口；安装 MySQL、NocoDB、Redis、Nginx、Supervisor、Python runtime | No | 修改基础镜像、MySQL/NocoDB 版本、系统包、复制路径、用户、端口、healthcheck 时 |
| `hfs-dev.toml` | HFS 范式对齐 manifest；声明 Pattern A、runtime 获取模式、Space root 模式、required files 和 release pin surface | No | 修改 HFS 分类、runtime 获取模式、发布态 pin 规则或新增必需文件时 |
| `.dockerignore` | Docker build context 过滤 | No | 修改 build context、排除规则或避免把本地文件打进镜像时 |
| `.codex/` | 本机 Codex agents/skills symlink 映射；当前不在 Git 跟踪内 | No | 仅在用户要求检查 Codex runtime、skill 或 agent 映射时读取；不要当作仓库权威内容 |
| `docker/` | runtime 配置和脚本：entrypoint、env、Supervisor、Nginx、MySQL、ops-service、healthcheck | Yes | 修改 `docker/` 下任意文件前先读 `docker/AGENTS.md` |
| `scripts/` | 本地 build、run、smoke、static check 脚本 | No | 修改开发者命令面、Docker 调用参数、smoke URL 或静态检查范围时 |
| `docs/` | 架构、配置、部署、开发、运维文档 | No | 修改 env var、端口、持久化、部署方式、运维步骤后同步检查相关文档 |
| `LICENSE` | GPL-3.0 license | No | 仅在用户明确要求处理许可文本时 |

## 按需 cat 协议

在编辑有本地 `AGENTS.md` 的目录前，先执行等价读取：

```bash
cat docker/AGENTS.md
```

读取后再决定改动。不要只依赖本文件对 `docker/` 的概述，因为 runtime 的端口、secret、只读诊断面和进程编排约束集中在子目录卡片里。

如果未来出现嵌套卡片，例如 `docker/subdir/AGENTS.md`，修改 `docker/subdir/file` 前先读 `docker/AGENTS.md`，再读 `docker/subdir/AGENTS.md`。

## 真实命令面

本仓库没有 `package.json`、`pyproject.toml`、`Makefile` 或 CI workflow 作为命令源。实际命令来自 `scripts/` 和 Dockerfile/脚本约定。

| Command | Purpose | Scope | Sandbox notes |
| --- | --- | --- | --- |
| `scripts/static-check.sh` | 运行 shell 语法检查、Python compile、`git diff --check` 和 `git diff --cached --check` | repo | 需要 `bash`、`python3`、`git`；不需要 Docker 或网络 |
| `bash -n docker/entrypoint.sh docker/healthcheck.sh scripts/build.sh scripts/run-demo.sh scripts/smoke.sh scripts/static-check.sh` | Shell 语法验证 | shell scripts | 默认可运行；不启动服务 |
| `python3 -m py_compile docker/ops_service.py` | Python 语法验证 | `docker/ops_service.py` | 默认可运行；仅使用 Python 标准库 |
| `git diff --check` | 工作区 whitespace 检查 | repo | 只读检查；需要 git workspace |
| `scripts/build.sh [image_tag]` | 构建 Docker 镜像，默认 `db-all-in-one-hfs:latest` | Docker image | 需要 Docker daemon；构建过程需要网络下载 apt/MySQL/NocoDB 依赖 |
| `scripts/run-demo.sh [image_tag]` | 本地启动 demo 容器，默认 named volume `db-hfs-persist` | local runtime | 需要 Docker daemon 和可用端口 `7860`；会删除同名运行容器 `db-aio-hfs-demo` |
| `scripts/smoke.sh [url]` | 检查 `/nginx-health`、`/healthz`、`/`，有 `OPS_TOKEN` 时检查 `/_ops/health` | running service | 需要目标服务已启动；默认访问 `http://localhost:7860`；使用 `curl` |

## 全局规则

- 始终把本仓库定位为 demo/all-in-one deployment bundle。
- 保持 Hugging Face Docker Space 约束：单容器、Nginx 监听 `7860`、容器运行 UID `1000`、持久化数据在 `/data`。
- `README.md` 的 `app_port: 7860`、`docker/nginx.conf` 的 `listen 7860`、`Dockerfile` 的 `EXPOSE 7860` 必须一致。
- `/data` 是 runtime persistence 边界。MySQL 数据、Redis 数据、NocoDB 数据、日志、runtime socket、generated secrets 都应留在 `/data` 下。
- entrypoint 生成的 secrets 属于 `/data/config/generated.env`。不要提交真实 secret，不要把 generated secret 写入 README、docs、test fixture、日志样例或 PR 文案。
- MySQL 和 Redis 是容器内部依赖；不要把它们的端口暴露到 Hugging Face Space 公网入口。
- MySQL 仅绑定 `127.0.0.1`，通过 NocoDB 使用；不要把本仓库改成公网 MySQL 服务。
- `ops-service` 是只读诊断面。`/_ops` 下只能提供健康、状态、日志、脱敏配置等只读能力。
- `ops-service` 的配置输出必须只包含 safe keys，不能返回 password、token、JWT secret、generated secret 或完整环境变量 dump。
- `NC_DEFAULT_LOCALE` 是本仓库 wrapper 层的 NocoDB UI 默认语言初始化变量，不是 NocoDB 官方 locale 环境变量；它通过 Nginx 注入 JS 写入浏览器 `localStorage`。
- Nginx 公开 wrapper 静态初始化文件时只能使用 exact path，例如 `/__db_aio/nocodb-locale-init.js`；公开文件放在 `/data/run/db-aio-public`，不要从 `/data/config` 服务任何静态文件。
- Nginx 对 `/signup` 和 `/signup/` 只做 exact 兼容重定向到 `/signin/`；不要通配重写 `/signup/<token>`，避免破坏潜在 token/invitation 路径。
- Shell 脚本保持 `#!/usr/bin/env bash` 与 `set -euo pipefail`。
- `docker/ops_service.py` 只使用 Python 标准库，不新增第三方 Python 依赖。
- 新增或重命名 env var 时同步检查 `docker/entrypoint.sh`、`docker/supervisord.conf`、`docker/ops_service.py`、`README.md` 和 `docs/configuration.md`。
- 修改端口或内部路由时同步检查 `Dockerfile`、`README.md`、`docker/nginx.conf`、`docker/supervisord.conf`、`docker/entrypoint.sh`、`docker/healthcheck.sh` 和 `scripts/smoke.sh`。
- 修改 Nginx HTML 注入或 `sub_filter` 逻辑时同步检查 `docker/nginx.conf`、`docker/entrypoint.sh`、`docs/architecture.md`、`docs/configuration.md`、`docs/development.md` 和浏览器 localStorage 验证步骤。
- 修改 MySQL/NocoDB 版本时只改明确的 version surface，并在最终说明中标注兼容性和迁移风险。
- 文档可以解释 demo 边界，但不要暗示本仓库已经具备生产备份、HA、审计、权限隔离或完整安全基线。
- `.codex/` 是本机忽略的 symlink 映射，不要把其目标目录内容当成 repo-private source of truth，也不要把它们提交进本仓库。

## Runtime 不变量

- 外部唯一公开入口是 Nginx `7860`。
- NocoDB 内部端口是 `8080`；`entrypoint.sh` 会要求 `PORT=8080`、`OPS_PORT=8081`。
- `ops-service` 内部端口是 `8081`，由 Nginx 映射到 `/_ops/`。
- MySQL socket 路径统一为 `/data/run/mysqld/mysqld.sock`。
- Redis 配置由 entrypoint 写入 `/data/run/redis.conf`。
- Supervisor 管理 `mysql`、`redis`、`nocodb`、`ops-service`、`nginx`。
- Nginx 注入 NocoDB 默认语言初始化脚本依赖 `ngx_http_sub_module`；Docker 镜像 runtime 验证时要检查 `nginx -V` 包含 `http_sub_module`。
- Docker runtime user 是 UID `1000`；不要引入需要 root runtime 权限的逻辑。
- Healthcheck 同时覆盖 NocoDB、`ops-service` 和 Nginx health endpoint。

## 修改指南

- 修改 `docker/` 下文件前先读 `docker/AGENTS.md`。
- 修改 `scripts/` 时保持参数向后兼容：`scripts/build.sh [image_tag]`、`scripts/run-demo.sh [image_tag]`、`scripts/smoke.sh [url]`。
- 修改 `scripts/run-demo.sh` 前确认是否会删除或复用本地容器/volume，并在最终说明中说明影响。
- 修改 `scripts/smoke.sh` 时不要默认要求 `OPS_TOKEN`；无 token 时应仍可完成公开端点 smoke。
- 修改 docs 时不要复制 secret 示例值；示例使用占位符。
- 修改 README front matter 时保持 Hugging Face Space 所需字段格式，尤其是 `sdk: docker` 和 `app_port: 7860`。

## 不要做

- 不要在用户没有明确要求时执行 `git push`、发布、部署或对外同步。
- 不要把 MySQL、Redis、NocoDB 内部端口直接暴露到 Space 公网入口。
- 不要在 `/_ops` 下新增写操作，例如重启服务、修改配置、执行 SQL、清理日志、生成 secret。
- 不要通过 ops config、logs、health response 暴露 secret 原文。
- 不要把 `NC_DEFAULT_LOCALE` 描述为 NocoDB 官方配置项；它只是本 demo wrapper 的首次 UI 语言初始化能力。
- 不要静默升级 MySQL 或 NocoDB 大版本。
- 不要新增长期依赖或包管理体系来解决一个小脚本问题；本仓库当前命令面是 Bash + Python 标准库 + Docker。
- 不要把 `/data` 持久化内容、runtime 生成文件、local volume 数据或 `.env` 内容提交到仓库。
- 不要把这个 demo 改成多容器 compose、Kubernetes chart、Terraform module 或生产部署目录，除非用户明确要求扩大范围。
- 不要在没有用户确认时删除持久化 volume 或执行会破坏本地数据的 Docker 命令。

## 验证标准

Shell/Python/文档级小改动的默认静态验证：

```bash
scripts/static-check.sh
```

等价拆分命令：

```bash
bash -n docker/entrypoint.sh docker/healthcheck.sh scripts/build.sh scripts/run-demo.sh scripts/smoke.sh scripts/static-check.sh
python3 -m py_compile docker/ops_service.py
git diff --check
```

涉及 Docker build 或 runtime 行为时，在 Docker 可用且用户允许的情况下运行：

```bash
scripts/build.sh
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -V 2>&1 | grep http_sub_module
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -t -c /etc/nginx/nginx.conf
scripts/run-demo.sh
scripts/smoke.sh http://localhost:7860
```

限制说明：

- `scripts/build.sh` 需要 Docker daemon，且构建期间需要网络下载 apt、MySQL 和 NocoDB 资源。
- `scripts/run-demo.sh` 需要 Docker daemon，会使用 named volume `db-hfs-persist`，并会删除同名容器 `db-aio-hfs-demo`。
- `scripts/smoke.sh` 需要服务已启动；如果检查 `/_ops/health`，还需要提供匹配的 `OPS_TOKEN`。
- 在受限环境或用户未要求验证时，不要假装已经跑过 Docker build/run/smoke；最终汇报中明确哪些命令未运行。

## 未来 agent 注意事项

- 这是小型 demo 仓库，优先做局部、可审计改动。
- 端口、secret、持久化和只读诊断面是最容易破坏的边界。
- 如果用户要求生产化，需要先回到需求层确认范围；不要直接在本仓库里堆生产基础设施。
- 如果引入新服务，至少要同步 Supervisor、Nginx、healthcheck、ops logs、README/docs 和 smoke 逻辑。
- 如果看到生成文件、volume 数据或 secret 样例进入 diff，先停下说明风险。
