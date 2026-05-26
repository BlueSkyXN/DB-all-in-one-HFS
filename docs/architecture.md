# 架构说明

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

## 启动流程

1. `tini` 作为 PID 1 init 进程
2. `entrypoint.sh` 执行：
   - 创建目录结构
   - 生成/加载 secrets（持久化到 `/data/config/generated.env`）
   - 初始化 MySQL 数据目录（首次运行）
   - 临时启动 MySQL 创建数据库和用户
   - 停止临时 MySQL
   - 写入 Redis 配置
   - 导出环境变量供子进程使用
   - 启动 supervisord
3. `supervisord` 按优先级启动：
   - MySQL (priority 10)
   - Redis (priority 20)
   - NocoDB (priority 40)
   - ops-service (priority 50)
   - Nginx (priority 80)

## 网络

- **对外**：仅 Nginx 端口 7860
- **对内**：MySQL 3306、NocoDB 8080、ops-service 8081、Redis 6379 均绑定 127.0.0.1

## 持久化

所有运行时数据存储在 `/data` 卷：

```
/data/
├── config/          # generated.env, supervisor.env
├── logs/            # 各服务日志
├── mysql/           # MySQL 数据文件
├── nocodb/          # NocoDB 元数据和上传文件
├── redis/           # Redis RDB 快照
└── run/             # PID 文件、socket、nginx temp
    ├── mysqld/
    └── nginx/
```

## 安全边界

- MySQL 不对外暴露，仅 NocoDB 通过 socket/TCP 127.0.0.1 连接
- Redis 不对外暴露，仅 NocoDB 使用
- ops-service 仅通过 Nginx `/_ops/` 路由访问，需 `OPS_TOKEN` 鉴权
- 密钥自动生成并持久化，重启不变
