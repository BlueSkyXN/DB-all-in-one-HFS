# 架构说明

`DB-all-in-one-HFS` 是 Hugging Face Docker Space demo bundle。它满足单容器和单公网入口约束，但并非生产级数据库平台：对外只有 Nginx `7860`，容器内由 Supervisor 管理多个内部服务。

## HFS v3 artifact 边界

这是 Pattern A port wrapper。GitHub main 是可写的 wrapper 与发布流程事实源；Space 只消费导出的 allowlisted wrapper，不保存 NocoDB 产品 rootfs、`local/`、`.env*`、缓存、生成数据或凭据。

```text
approved GitHub commit
  ├─ publish workflow: pinned OCI ref -> rootfs archive -> readback -> manifest-last
  ├─ GitHub Release: immutable historical archive (tag releases)
  └─ hfs-dist/db-all-in-one-hfs/{edge,release}/
       ├─ nocodb-runtime-<tag>-<wrapper-commit>.tar.gz
       └─ manifest.json -> the one current archive

Space startup
  manifest URL -> validate -> one archive download -> SHA-256/layout check
  -> container-local /home/user/run/nocodb-runtime/rootfs -> NocoDB
```

`manifest.json` 的最小运行契约由 `docker/nocodb_bootstrap.py` 实施：schema version、项目、slot、`oci-image` source ref、与导出 Dockerfile 固化值相同的完整 wrapper Git SHA、生成时间、唯一 archive 名称、无凭据且无 query/fragment 的 HTTPS URL、大小和 SHA-256 都必须匹配。它不扫描 slot、不接受直接 archive 输入、不使用旧 runtime 或 OCI build-stage fallback。解包前拒绝路径穿越、设备、FIFO，以及指向 `rootfs/` 外的硬链接或软链接；解包后校验本机架构所需 musl loader、可执行 Node 和 NocoDB entrypoint。

## 容器内组件

```text
┌─────────────────────────────────────────────────────────────┐
│                 Docker Container (UID 1000)                  │
│  nginx :7860 ──┬── NocoDB :8080 (127.0.0.1)                 │
│                └── ops-service :8081 (127.0.0.1)             │
│  MySQL :3306 (127.0.0.1)   Redis :6379 (127.0.0.1)           │
│  tini -> entrypoint -> supervisord                            │
└─────────────────────────────────────────────────────────────┘
```

Dockerfile 只安装 Ubuntu、MySQL、Redis、Nginx、Supervisor、Python 和 bootstrap wrapper。`NOCODB_SOURCE_REF` 仍以官方 tag + OCI digest 固定来源，但该 OCI image 不再作为 Docker multi-stage runtime。为兼容 musl Node，镜像在构建时仅设置一个指向固定容器本地 runtime 位置的 loader link；该 link 在成功 bootstrap 前不可用，因而失败会停止启动而不是伪健康。

## 启动顺序

1. `tini` 启动 `entrypoint.sh`。
2. 验证 `/data` 与固定端口/locale 约束；先执行 artifact bootstrap。
3. bootstrap 成功后创建运行目录、加载或生成 secret、初始化容器本地 MySQL datadir。
4. 临时启动 MySQL，创建数据库/用户，从 `/data/backups` 中由新到旧恢复第一份可读逻辑 dump，然后交给 Supervisor。
5. Supervisor 启动 MySQL、Redis、NocoDB、ops-service 和 Nginx。

因此 manifest 或 archive 失败发生在 MySQL 初始化、secret 写入、备份恢复和 Supervisor 启动之前，避免 artifact 下载失败改动持久化应用状态。

## 持久化与恢复

HF bucket mount 是 FUSE 对象存储，不适合 unix socket、InnoDB redo 或 Redis RDB 的 rename 语义：

```text
/data/                         # 挂载面：只存普通文件
├── config/                    # generated.env、supervisor.env（敏感）
├── logs/
├── backups/nocodb-*.sql.gz    # MySQL 逻辑 dump；create/read/delete only
└── nocodb/                    # 应用数据与上传文件

/home/user/                    # 容器本地，重启后需重建
├── mysql/                     # InnoDB datadir
├── redis/                     # Redis RDB
└── run/                       # socket、pid、Nginx temp、artifact runtime
```

`mysql-backup` 定期创建 timestamped gzip dump 并执行 `gzip -t`；停止时再执行一次。启动恢复只读取 `/data/backups/nocodb-*.sql.gz`，按文件名从新到旧尝试，跳过损坏或上传不完整的 dump。不要把 MySQL/Redis datadir 移到 `/data`，不要把 artifact archive 或 runtime rootfs 挂载到 `/data`，也不要在未隔离演练的情况下对真实数据执行 restore。

## 健康、Provenance 与诊断

Docker healthcheck 依次请求 NocoDB、ops-service 和 Nginx。公开 `/healthz` 只有全部内部依赖正常才返回 200。认证后的 `/_ops/provenance` 输出已验证的 `source_ref`、wrapper SHA、slot、archive 名称、SHA-256 和生成时间，不输出 artifact URL、Settings、secret 或完整环境。
