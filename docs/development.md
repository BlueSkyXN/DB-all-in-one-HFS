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

## 构建与测试

```bash
# 构建镜像
scripts/build.sh

# 运行 demo
scripts/run-demo.sh

# Smoke 测试
scripts/smoke.sh http://localhost:7860
```

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
- `README.md` (app_port)
- `Dockerfile` (EXPOSE)

### 新增环境变量

同步检查：
- `docker/entrypoint.sh` (defaults + export)
- `docker/ops_service.py` (if safe to expose in /config)
- `Dockerfile` (build args / ENV if applicable)
- `docs/configuration.md`

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
