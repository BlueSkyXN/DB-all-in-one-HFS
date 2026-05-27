# 架构说明

`DB-all-in-one-HFS` 是一个 Hugging Face Docker Space demo bundle。它优先满足 HF Docker Space 的单容器入口约束：容器内可以有多个进程，但对外只暴露 Nginx 的 `7860`。

## 容器内组件

```text
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container (UID 1000)               │
│                                                             │
│  ┌──────────────────┐     ┌──────────────────────────────┐ │
│  │  Nginx (:7860)   │────▶│  NocoDB (:8080)              │ │
│  │  reverse proxy   │     │  Database UI / REST / GQL    │ │
│  └────────┬─────────┘     └──────────────┬───────────────┘ │
│           │                              │                  │
│           │  /_ops/                       │                  │
│           ▼                              ▼                  │
│  ┌──────────────────┐     ┌──────────────────────────────┐ │
│  │  ops-service     │     │  MySQL 9.7 LTS (:3306)       │ │
│  │  (:8081)         │     │  127.0.0.1 only              │ │
│  └──────────────────┘     └──────────────────────────────┘ │
│                                                             │
│                           ┌──────────────────────────────┐ │
│                           │  Redis (:6379)               │ │
│                           │  NocoDB cache layer          │ │
│                           └──────────────────────────────┘ │
│                                                             │
│  Process Manager: supervisord                               │
│  Init: tini                                                 │
└─────────────────────────────────────────────────────────────┘
```

所有进程都在镜像的 `USER 1000` 下运行。镜像构建阶段安装 MySQL、Redis、Nginx、Supervisor、Python 和 NocoDB 二进制；运行阶段不需要 root 权限。

## 启动流程

1. `tini` 作为 PID 1 init 进程
2. `entrypoint.sh` 执行：
   - 创建目录结构
   - 生成/加载 secrets（持久化到 `/data/config/generated.env`）
   - 校验固定内部端口：`PORT=8080`、`OPS_PORT=8081`
   - 初始化 MySQL 数据目录（首次运行）
   - 临时启动 MySQL 创建数据库和用户
   - 停止临时 MySQL
   - 写入 `/data/run/redis.conf`
   - 导出 NocoDB、Redis、MySQL、ops-service 所需环境变量
   - 写入 `/data/run/db-aio-public/nocodb-locale-init.js`，用于初始化 NocoDB UI 默认语言
   - 写入 `/data/config/supervisor.env` 作为诊断用快照
   - 启动 supervisord
3. `supervisord` 按优先级启动：
   - MySQL (priority 10)
   - Redis (priority 20)
   - NocoDB (priority 40)
   - ops-service (priority 50)
   - Nginx (priority 80)

## 网络

| 服务 | 地址 | 外部可达 | 说明 |
| --- | --- | --- | --- |
| Nginx | `0.0.0.0:7860` | Yes | HF Space `app_port`，唯一公网入口 |
| NocoDB | `127.0.0.1:8080` | No | 由 Nginx 代理 `/` 和 `/socket.io/` |
| ops-service | `127.0.0.1:8081` | No | 由 Nginx 代理 `/healthz` 和 `/_ops/` |
| MySQL | `127.0.0.1:3306` | No | NocoDB 通过 TCP 连接；CLI/health 可用 Unix socket |
| Redis | `127.0.0.1:6379` | No | NocoDB 缓存层 |

Nginx 路由：

| 外部路径 | 上游 | 鉴权 |
| --- | --- | --- |
| `/` | NocoDB `http://127.0.0.1:8080` | NocoDB 自身鉴权 |
| `/socket.io/` | NocoDB WebSocket | NocoDB 自身鉴权 |
| `/__db_aio/nocodb-locale-init.js` | Nginx 本地静态文件 | 无 |
| `/nginx-health` | Nginx 本地响应 | 无 |
| `/healthz` | ops-service `/healthz` | 无 |
| `/_ops/` | ops-service `/` | `OPS_TOKEN` |
| `/_ops/*` | ops-service `/*` | 除 `/_ops/healthz` 外需要 `OPS_TOKEN` |

## 持久化

所有运行时数据存储在 `/data` 卷：

```
/data/
├── config/          # generated.env, supervisor.env
├── logs/            # supervisor、MySQL、Redis、NocoDB、Nginx stdout 日志
├── mysql/           # MySQL 数据文件
├── nocodb/          # NocoDB 元数据和上传文件
├── redis/           # Redis RDB 快照
└── run/             # PID 文件、socket、redis.conf、nginx temp
    ├── db-aio-public/  # Nginx 公开的 wrapper 静态初始化文件
    ├── mysqld/
    └── nginx/
```

`DATA_DIR` 在入口脚本中有默认值，但当前镜像的 Supervisor、MySQL、Nginx、healthcheck 和脚本都围绕 `/data` 写死。不要把它当成可随意改动的运行时开关。

## 安全边界

- MySQL 不对外暴露；NocoDB 通过 `mysql2://127.0.0.1:3306` 连接
- Redis 不对外暴露，仅 NocoDB 使用
- ops-service 只提供 `GET` 只读诊断接口，不提供写操作
- `/_ops/healthz` 和 `/healthz` 不需要 token；其他 `/_ops` 诊断接口需要 `OPS_TOKEN`
- `/_ops/config` 只返回白名单配置，不返回 MySQL 密码、JWT secret 或 ops token
- 密钥自动生成并持久化，保存在 `/data/config/generated.env`，重启不变

## 健康检查

Docker `HEALTHCHECK` 依次检查：

```text
http://127.0.0.1:8080/api/v1/health
http://127.0.0.1:8081/healthz
http://127.0.0.1:7860/nginx-health
```

对外可用的综合健康接口是 `/healthz`。它由 ops-service 检查 MySQL、Redis 和 NocoDB，并在任一检查失败时返回 `503`。
