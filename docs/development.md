# 开发指南

## 前提

- Docker (BuildKit)
- Bash
- Python 3 (用于 syntax check)

## 静态检查

```bash
scripts/static-check.sh
```

包含：
- `bash -n` 检查所有 shell 脚本语法
- `python3 -m py_compile` 检查 ops_service.py
- `git diff --check` 检查空白字符
- `git diff --cached --check` 检查已暂存内容的空白字符

## 构建与测试

```bash
# 构建镜像
scripts/build.sh

# 构建发布态候选镜像时显式 pin NocoDB release 和 SHA256
NOCODB_RELEASE=<release-tag> \
NOCODB_SHA256=<sha256> \
scripts/build.sh db-all-in-one-hfs:<release-tag>

# 运行 demo
scripts/run-demo.sh

# Smoke 测试公开端点
scripts/smoke.sh http://localhost:7860
```

脚本参数：

| Script | 参数 | 默认值 |
| --- | --- | --- |
| `scripts/build.sh` | image tag | `db-all-in-one-hfs:latest` |
| `scripts/run-demo.sh` | image tag | `db-all-in-one-hfs:latest` |
| `scripts/smoke.sh` | base URL | `http://localhost:7860` |

`scripts/build.sh` 会透传 `UBUNTU_VERSION`、`MYSQL_VERSION`、`MYSQL_SERVER_PACKAGE`、`MYSQL_CLIENT_PACKAGE`、`NOCODB_RELEASE` 和 `NOCODB_SHA256` 环境变量为 Docker build args。默认 auto/latest 构建用于开发；发布态构建需要显式 pin release 和 checksum，并可按需 pin MySQL package spec。

Docker healthcheck 与 smoke 脚本不是同一层检查：

- `docker/healthcheck.sh` 在容器内检查 NocoDB、ops-service 和 Nginx
- `scripts/smoke.sh` 从外部检查 `/nginx-health`、`/healthz` 和 NocoDB 根路径

ops 鉴权端点建议用 `curl -H "X-Ops-Token: $OPS_TOKEN"` 单独验证，不把它和公开 smoke 混在一起判断。

## 修改检查清单

### Shell 脚本修改

```bash
bash -n docker/entrypoint.sh docker/healthcheck.sh scripts/*.sh
```

### Python 修改

```bash
python3 -m py_compile docker/ops_service.py
```

### Nginx/端口修改

同步检查：
- `docker/nginx.conf` (listen / proxy_pass)
- `docker/supervisord.conf` (command ports)
- `docker/entrypoint.sh` (env defaults)
- `docker/healthcheck.sh` (check URLs)
- `docs/configuration.md`
- `docs/architecture.md`
- `README.md` (app_port)
- `Dockerfile` (EXPOSE)

### 新增环境变量

同步检查：
- `docker/entrypoint.sh` (defaults + export)
- `docker/ops_service.py` (if safe to expose in /config)
- `Dockerfile` (build args / ENV if applicable)
- `docs/configuration.md`

### Secret 或诊断面修改

同步检查：
- `docker/entrypoint.sh` 生成和持久化逻辑
- `docker/ops_service.py` 是否会泄露敏感值
- `docs/configuration.md` 的 secret 管理和 ops endpoint 表
- `docs/ops-runbook.md` 的排障命令

`ops-service` 是只读诊断面。不要在 `/_ops` 下新增写操作。

## 文件职责

| File | Role |
| --- | --- |
| `Dockerfile` | 构建入口，系统包安装，资产复制 |
| `docker/entrypoint.sh` | 启动初始化：secret 生成、MySQL bootstrap、启动 supervisord |
| `docker/supervisord.conf` | 进程管理配置 |
| `docker/nginx.conf` | 反向代理路由 |
| `docker/my.cnf` | MySQL 性能和日志配置 |
| `docker/healthcheck.sh` | Docker HEALTHCHECK |
| `docker/ops_service.py` | 只读诊断 HTTP 服务 |
| `scripts/build.sh` | 镜像构建 wrapper |
| `scripts/run-demo.sh` | 本地运行 wrapper |
| `scripts/smoke.sh` | HTTP smoke 测试 |
| `scripts/static-check.sh` | 静态检查聚合 |

## Build Context

`.dockerignore` 会排除 `README.md`、`docs/` 和其他 Markdown 文件，避免文档进入镜像 build context。HF Space 仍会读取仓库根目录的 `README.md` 作为 Space card；这与 Docker build context 无关。

## 提交前建议

文档-only 修改至少运行：

```bash
git diff --check
```

Shell/Python/runtime 修改运行：

```bash
scripts/static-check.sh
```

如果 Docker 可用且改动影响启动路径，继续运行：

```bash
scripts/build.sh
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -V 2>&1 | grep http_sub_module
docker run --rm --entrypoint nginx db-all-in-one-hfs:latest -t -c /etc/nginx/nginx.conf
scripts/run-demo.sh
scripts/smoke.sh http://localhost:7860
```
