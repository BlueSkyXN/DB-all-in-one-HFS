# 仓库 Agent 指令

## 项目定位

`DB-all-in-one-HFS` 是面向 Hugging Face Docker Space 的 MySQL 9.7 LTS + NocoDB 单容器 demo bundle。它把 MySQL、NocoDB、Redis、Nginx、Supervisor 和只读 `ops-service` 收敛到一个容器内，用于数据库可视化管理演示和轻量 PoC。

本仓库是 **HFS Port Repository**：仓库根目录同时是 GitHub 维护根和 Hugging Face Space root。不要把 Space 文件迁入 `cloud/hfs/`；那是 HFS Deployment Adapter 形态，不适用于本仓库。

本仓库不是生产部署方案。不要把它描述、改造或包装成生产级数据库平台；生产环境应使用独立 MySQL 服务，并补齐高可用、备份、鉴权、监控、容量规划和正式运维流程。

## Codex 启动行为

- Codex 通常从仓库根目录启动；本文件是 repo-local 启动期主规则。
- 子目录 `AGENTS.md` 是按需导航卡片，不会在根启动 workflow 中自动进入上下文。
- 修改有本地 `AGENTS.md` 的目录前，必须先读取该目录的本地卡片。
- 如果未来新增更深层 `AGENTS.md`，修改目标文件前按从浅到深顺序读取路径链上的卡片。
- 如果从子目录启动，Codex 也可能自动加载路径链上的本地 `AGENTS.md`；冲突时以更接近目标文件的规则为准。

## 目录地图

| Path | Responsibility | Local AGENTS.md | Read when |
| --- | --- | ---: | --- |
| `README.md` | Hugging Face Space card、项目介绍、本地运行和部署入口 | No | 修改项目定位、HF metadata、`sdk: docker`、`app_port`、端口说明或公开文档入口时 |
| `Dockerfile` | Docker Space 镜像构建入口；安装 MySQL、NocoDB、Redis、Nginx、Supervisor、Python runtime | No | 修改基础镜像、MySQL/NocoDB 版本、APT 包、复制路径、运行用户、端口、healthcheck 或 build args 时 |
| `hfs-dev.toml` | HFS 范式 manifest；声明 Pattern A、artifact-at-build-time、repo-root Space、required files 和 release pin surface | No | 修改 HFS 分类、runtime 获取模式、Space root 模式、required files、health endpoint、public port 或 release pin 规则时 |
| `.github/` | GitHub Actions；当前只有 `static-check` workflow | No | 修改 CI 触发条件、permissions、checkout 或验证命令时 |
| `.dockerignore` | Docker build context 过滤 | No | 修改 build context、排除规则或避免把本地文件、文档、secret 打进镜像时 |
| `.gitattributes` / `.gitignore` | Git 归一化和忽略规则 | No | 修改换行策略、忽略生成物、local runtime 文件或 secret 文件规则时 |
| `.codex/` | 本机 Codex agents/skills symlink 映射；当前不在 Git 跟踪内 | No | 仅在用户要求检查 Codex runtime、skill 或 agent 映射时读取；不要当作仓库权威内容 |
| `docker/` | runtime 配置和脚本：entrypoint、env、Supervisor、Nginx、MySQL、ops-service、healthcheck | Yes | 修改 `docker/` 下任意文件前先读 `docker/AGENTS.md` |
| `scripts/` | 本地 build、run、smoke、static check wrapper | No | 修改开发者命令面、Docker 调用参数、smoke URL、默认容器名、默认 volume 或静态检查范围时 |
| `docs/` | 架构、配置、部署、开发、运维文档 | No | 修改 env var、端口、持久化、部署方式、ops endpoint、runtime 行为或运维步骤后同步检查相关文档 |
| `LICENSE` | GPL-3.0 license | No | 仅在用户明确要求处理许可文本时 |

## 按需 cat 协议

在编辑有本地 `AGENTS.md` 的目录前，先执行等价读取：

```bash
cat docker/AGENTS.md
```

读取后再决定改动。不要只依赖本文件对 `docker/` 的概述，因为 runtime 的端口、secret、只读诊断面和进程编排约束集中在子目录卡片里。

如果未来出现嵌套卡片，例如 `docker/subdir/AGENTS.md`，修改 `docker/subdir/file` 前先读 `docker/AGENTS.md`，再读 `docker/subdir/AGENTS.md`。

## 真实命令面

本仓库没有 `package.json`、`pyproject.toml`、`Makefile`、`docker-compose.yml` 或包管理器 lockfile。实际命令来自 `scripts/`、`Dockerfile`、`.github/workflows/static-check.yml` 和 `docs/development.md`。

| Command | Purpose | Scope | Sandbox notes |
| --- | --- | --- | --- |
| `scripts/static-check.sh` | 聚合静态检查：shell syntax、可选 ShellCheck、Python compile、`git diff --check` 和 `git diff --cached --check` | repo | 需要 `bash`、`python3`、`git`；有 `shellcheck` 时会额外运行；不需要 Docker 或网络 |
| `bash -n docker/entrypoint.sh docker/healthcheck.sh docker/nocodb.sh scripts/*.sh` | Shell 语法验证 | shell scripts | 默认可运行；不启动服务 |
| `python3 -m py_compile docker/ops_service.py` | Python 语法验证 | `docker/ops_service.py` | 默认可运行；仅使用 Python 标准库 |
| `git diff --check && git diff --cached --check` | 工作区和暂存区 whitespace 检查 | repo | 只读检查；需要 Git workspace |
| `scripts/build.sh [image_tag]` | 构建 Docker 镜像，默认 `db-all-in-one-hfs:latest` | Docker image | 需要 Docker daemon；构建过程可能下载 apt/MySQL metadata，并拉取 pinned NocoDB OCI image |
| `NOCODB_IMAGE_REF='nocodb/nocodb:<tag>@sha256:<digest>' scripts/build.sh db-all-in-one-hfs:<tag>` | 构建指定 NocoDB OCI 候选镜像 | Docker image | 需要 Docker daemon 和网络；image ref 必须保留 release tag + digest |
| `docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -V 2>&1 \| grep http_sub_module` | 验证镜像 Nginx 包含 `ngx_http_sub_module` | built image | 需要 Docker daemon 和已构建镜像 |
| `docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -t -c /etc/nginx/nginx.conf` | 验证镜像内 Nginx config | built image | 需要 Docker daemon 和已构建镜像 |
| `scripts/run-demo.sh [image_tag]` | 本地启动 demo 容器，默认 image tag `db-all-in-one-hfs:latest` | local runtime | 需要 Docker daemon 和可用端口 `7860`；会删除同名运行容器 `db-aio-hfs-demo`，并复用 named volume `db-hfs-persist` |
| `scripts/smoke.sh [url]` | 从外部检查 `/nginx-health`、`/healthz` 和 NocoDB 根路径；默认 `http://localhost:7860` | running service | 需要目标服务已启动和 `curl`；公开 smoke 默认不要求 `OPS_TOKEN` |
| `curl -H "X-Ops-Token: $OPS_TOKEN" <url>/_ops/status` | 单独验证 ops 鉴权诊断面 | running service | 需要运行中的服务和有效 `OPS_TOKEN`；不要把 token 写入日志、README、PR 或公开材料 |

## 全局规则

- 始终把本仓库定位为 demo/all-in-one deployment bundle，不要暗示生产级 HA、备份、审计、权限隔离或完整安全基线已经具备。
- 保持 Hugging Face Docker Space 约束：单容器、repo root 是 Space root、Nginx 监听 `7860`、容器运行 UID `1000`、持久化数据在 `/data`。
- `README.md` front matter 的 `app_port: 7860`、`hfs-dev.toml` 的 `public_port = 7860`、`docker/nginx.conf` 的 `listen 7860`、`Dockerfile` 的 `EXPOSE 7860` 必须一致。
- `hfs-dev.toml` 当前声明 `pattern = "A"`、`runtime_mode = "artifact-at-build-time"`、`space_root_mode = "repo-root"`、`canonical_health_endpoint = "/healthz"`；修改这些字段时同步检查 README、Dockerfile、scripts 和 docs。
- `/data` 是 runtime persistence 边界。MySQL 数据、Redis 数据、NocoDB 数据、日志、runtime socket、generated secrets 和 wrapper public JS 都应留在 `/data` 下。
- `DATA_DIR` 在配置文档中可见，但当前 Supervisor、Nginx、MySQL socket、healthcheck 和脚本都围绕 `/data` 写死；不要把它当成可自由切换的 runtime 开关。
- entrypoint 生成的 secrets 属于 `/data/config/generated.env`；`/data/config/supervisor.env` 也是敏感诊断快照。不要提交真实 secret，不要把 generated secret 写入 README、docs、test fixture、日志样例、PR 文案或 public catalog。
- MySQL 和 Redis 是容器内部依赖；不要把它们的端口暴露到 Hugging Face Space 公网入口。
- MySQL 仅绑定 `127.0.0.1`，NocoDB 通过 `mysql2://127.0.0.1:3306` 使用；不要把本仓库改成公网 MySQL 服务。
- 外部唯一公开入口是 Nginx `7860`；NocoDB 内部端口是 `8080`，`ops-service` 内部端口是 `8081`，Redis 是 `6379`，MySQL socket 是 `/data/run/mysqld/mysqld.sock`。
- `ops-service` 是只读诊断面。`/_ops` 下只能提供健康、状态、日志、脱敏配置等只读能力。
- `ops-service` 的 `/config` 输出必须只包含 safe keys，不能返回 password、token、JWT secret、generated secret、完整环境变量 dump 或未脱敏日志。
- `NC_DEFAULT_LOCALE` 是本 demo wrapper 层的 NocoDB UI 默认语言初始化变量，不是 NocoDB 官方 locale 环境变量；它通过 Nginx 注入 JS 写入浏览器 `localStorage`。
- Nginx 公开 wrapper 静态初始化文件时只能使用 exact path，例如 `/__db_aio/nocodb-locale-init.js`；公开文件放在 `/data/run/db-aio-public`，不要从 `/data/config` 服务任何静态文件。
- Nginx 对 `/signup` 和 `/signup/` 只做 exact 兼容重定向到 `/signin/`；不要通配重写 `/signup/<token>`，避免破坏潜在 token/invitation 路径。
- Nginx HTML 注入依赖 `ngx_http_sub_module` 和 `Accept-Encoding ""`；修改 `sub_filter` 或 `location /` 时同步验证镜像内 `nginx -V` 和 `nginx -t`。
- Shell 脚本保持 `#!/usr/bin/env bash` 与 `set -euo pipefail`。
- `docker/ops_service.py` 只使用 Python 标准库，不新增第三方 Python 依赖或包管理体系。
- NocoDB runtime 来自 pinned 官方 OCI image，并完整保存在 `/opt/nocodb-runtime`；`docker/nocodb.sh` 负责启动其中的 musl Node runtime，不要退回已停止发布的 `Noco-linux-*` executable 下载路径。
- 新增长期依赖前先确认是否可以用现有 Bash、Python 标准库、Dockerfile package 或 Nginx/Supervisor 配置解决。
- 修改 MySQL/NocoDB 版本时只改明确的 version surface，并在最终说明中标注兼容性、迁移和 release pin 风险。
- 发布态构建必须保持 `UBUNTU_VERSION`、`MYSQL_SERVER_PACKAGE` / `MYSQL_CLIENT_PACKAGE` 和 `NOCODB_IMAGE_REF` 不可变；当前默认值已经 pin 到 Ubuntu digest、MySQL 9.7.1 和 NocoDB `2026.07.0` OCI digest。

## 联动修改规则

- 修改 `docker/` 下文件前先读 `docker/AGENTS.md`。
- 修改 `scripts/` 时保持参数向后兼容：`scripts/build.sh [image_tag]`、`scripts/run-demo.sh [image_tag]`、`scripts/smoke.sh [url]`。
- 修改 `scripts/run-demo.sh` 前确认是否会删除或复用本地容器/volume，并在最终说明中说明影响。
- 修改 `scripts/smoke.sh` 时不要默认要求 `OPS_TOKEN`；公开 smoke 应能在无 token 时完成。ops 鉴权端点用带 `X-Ops-Token` header 的单独 curl 验证。
- 新增或重命名 env var 时同步检查 `docker/entrypoint.sh`、`docker/supervisord.conf`、`docker/ops_service.py`、`README.md`、`docs/configuration.md`、`docs/deployment.md` 和 `docs/ops-runbook.md`。
- 修改端口或内部路由时同步检查 `Dockerfile`、`README.md`、`hfs-dev.toml`、`docker/nginx.conf`、`docker/supervisord.conf`、`docker/entrypoint.sh`、`docker/healthcheck.sh`、`scripts/smoke.sh`、`docs/architecture.md` 和 `docs/configuration.md`。
- 修改 Nginx HTML 注入或 locale init 逻辑时同步检查 `docker/nginx.conf`、`docker/entrypoint.sh`、`docs/architecture.md`、`docs/configuration.md`、`docs/development.md` 和浏览器 `localStorage` 验证步骤。
- 修改 `ops-service` endpoint、日志服务名或 safe config keys 时同步检查 `docker/ops_service.py`、`docs/configuration.md`、`docs/ops-runbook.md` 和 `scripts/smoke.sh` 是否受影响。
- 修改 Docker build args、release pin surface 或 required files 时同步检查 `Dockerfile`、`hfs-dev.toml`、`README.md`、`docs/configuration.md` 和 `docs/deployment.md`。
- 修改 docs 时不要复制 secret 示例值；示例使用占位符。
- 修改 README front matter 时保持 Hugging Face Space 所需字段格式，尤其是 `sdk: docker` 和 `app_port: 7860`。

## 不要做

- 不要在用户没有明确要求时执行 `git push`、发布、部署或对外同步。
- 不要把这个 demo 改成多容器 compose、Kubernetes chart、Terraform module、生产部署目录或通用数据库平台，除非用户明确要求扩大范围。
- 不要把 MySQL、Redis、NocoDB 或 `ops-service` 内部端口直接暴露到 Space 公网入口。
- 不要在 `/_ops` 下新增写操作，例如重启服务、修改配置、执行 SQL、清理日志、生成 secret 或 rotate secret。
- 不要通过 ops config、logs、health response、README、docs、截图或 PR 文案暴露 secret 原文。
- 不要把 `NC_DEFAULT_LOCALE` 描述为 NocoDB 官方配置项；它只是本 demo wrapper 的首次 UI 语言初始化能力。
- 不要静默升级 MySQL 或 NocoDB 大版本。
- 不要新增长期依赖或包管理体系来解决一个小脚本问题；本仓库当前命令面是 Bash + Python 标准库 + Docker。
- 不要把 `/data` 持久化内容、runtime 生成文件、local volume 数据、`.env` 内容、`*.secret`、`*.key` 或 `*.pem` 提交到仓库。
- 不要在没有用户确认时删除持久化 volume、执行破坏本地数据的 Docker 命令，或清理用户未授权的外部资源。
- 不要把 `.codex/` symlink 目标目录内容当成 repo-private source of truth，也不要把它们提交进本仓库。

## 验证标准

Shell/Python/文档级小改动的默认静态验证：

```bash
scripts/static-check.sh
```

等价拆分命令：

```bash
bash -n docker/entrypoint.sh docker/healthcheck.sh docker/nocodb.sh scripts/*.sh
python3 -m py_compile docker/ops_service.py
git diff --check
git diff --cached --check
```

涉及 Docker build 或 runtime 行为时，在 Docker 可用且用户允许的情况下运行：

```bash
scripts/build.sh
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -V 2>&1 | grep http_sub_module
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -t -c /etc/nginx/nginx.conf
scripts/run-demo.sh
scripts/smoke.sh http://localhost:7860
```

需要验证 ops 鉴权诊断面时，使用单独 curl，不要把 token 写进持久日志或公开材料：

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/status
```

限制说明：

- `scripts/static-check.sh` 是 GitHub Actions 当前唯一 CI 验证入口。
- `scripts/static-check.sh` 会在 `shellcheck` 存在时运行 ShellCheck；不存在时跳过，这是脚本的预期行为。
- `scripts/build.sh` 需要 Docker daemon，且构建期间可能需要网络下载 apt、MySQL 和 NocoDB 资源。
- `scripts/run-demo.sh` 需要 Docker daemon，会删除同名运行容器 `db-aio-hfs-demo`，会使用 named volume `db-hfs-persist`，并需要本机端口 `7860` 可用。
- `scripts/smoke.sh` 需要服务已启动；公开 smoke 不需要 `OPS_TOKEN`。
- 在受限环境或用户未要求验证时，不要假装已经跑过 Docker build/run/smoke；最终汇报中明确哪些命令未运行。

## 未来 agent 注意事项

- 这是小型 demo 仓库，优先做局部、可审计改动。
- 端口、secret、持久化、release pin 和只读诊断面是最容易破坏的边界。
- 如果用户要求生产化，需要先回到需求层确认范围；不要直接在本仓库里堆生产基础设施。
- 如果引入新服务，至少要同步 Supervisor、Nginx、healthcheck、ops logs、README/docs、smoke 逻辑和 HFS required files。
- 如果看到生成文件、volume 数据或 secret 样例进入 diff，先停下说明风险。
