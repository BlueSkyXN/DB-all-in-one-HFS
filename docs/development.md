# 开发指南

## 静态检查

```bash
scripts/static-check.sh
python3 /Users/sky/Github/SKY-Prompt/hfs-dev/scripts/check_hfs_alignment.py .
git diff --check
git diff --cached --check
```

`static-check.sh` 执行 shell syntax、可选 ShellCheck、Python compile、MySQL config invariant、HFS artifact contract 和离线 bootstrap tests。artifact tests 只在临时目录生成合成 archive，不读取 `.env`、`local/`、volume、数据库或网络资源。

HFS shared checker 验证最小 `hfs-dev.toml` v2 registry；项目自己的 pin、checksum、manifest schema、bootstrap、persistence/backup 约束由 `Dockerfile`、`docker/nocodb_bootstrap.py` 和 `scripts/check-hfs-artifact-contract.sh` 直接验证，避免形成第二份 pin truth。

## 构建和本地 smoke

```bash
scripts/build.sh

# NOCODB_IMAGE_REF 是兼容别名；新调用使用 NOCODB_SOURCE_REF。
NOCODB_SOURCE_REF='nocodb/nocodb:<tag>@sha256:<digest>' \
scripts/build.sh db-all-in-one-hfs:test

NOCODB_ARTIFACT_MANIFEST_URL='https://<approved-dist-host>/db-all-in-one-hfs/release/manifest.json' \
NOCODB_ARTIFACT_SLOT='release' \
scripts/run-demo.sh db-all-in-one-hfs:test
scripts/smoke.sh http://localhost:7860
```

Docker build 仍可能下载 Ubuntu/MySQL APT 内容。`run-demo` 会删除同名容器 `db-aio-hfs-demo`、复用 `db-hfs-persist` volume，并通过 HTTPS 下载 manifest/archive；不要把它用于真实数据库、真实 artifact endpoint 或未备份的本地数据。Docker build/run/smoke 不是静态检查的一部分。

## Artifact producer 与 consumer

- Producer：`publish-nocodb-artifact.yml` 在明确确认后拉取 Dockerfile 的 immutable `NOCODB_SOURCE_REF`，导出 `rootfs/` archive；先 readback archive，再 manifest-last。tag 的历史 archive 由 GitHub Release 保存。
- Consumer：`docker/nocodb_bootstrap.py` 在 entrypoint 的 MySQL 初始化之前使用 `NOCODB_ARTIFACT_MANIFEST_URL` 下载一次 manifest 和其中唯一 archive，校验 source ref、已固化的 wrapper Git SHA、size、SHA-256 和布局；不接受 direct archive、目录扫描或 fallback。
- Wrapper deploy：`scripts/export-space-bundle.sh <empty-dir>` 只导出 allowlisted Pattern A wrapper，将完整 Git SHA 固化为导出 Dockerfile 的 `WRAPPER_SOURCE_REF`，并生成相同 SHA 的 `BUILD_SOURCE.json`。它拒绝 dirty Git worktree，且不上传任何内容。

在修改 bootstrap、archive schema、pin 或 exporter 时，必须同步修改 `Dockerfile`、`docker/entrypoint.sh`、`docker/nocodb.sh`、`docker/nocodb_bootstrap.py`、artifact contract tests、`hfs-dev.toml`、Space/deployment docs 和 workflow readback。

## 运行时不变量

- Nginx `7860` 是唯一公网入口；NocoDB `8080`、ops-service `8081`、MySQL/Redis 只在 `127.0.0.1`。
- `/data` 只存普通持久文件。MySQL datadir 必须为 `/home/user/mysql`，Redis 为 `/home/user/redis`；不要在 FUSE mount 上使用 InnoDB redo/RDB。
- 下载 runtime 位于 `/home/user/run/nocodb-runtime`，不是 `/data`，启动失败不能污染数据库持久化面。
- `mysql-backup.sh` 使用新文件/读取/删除，而不依赖 tmp+rename；恢复按最新到最旧可读 dump。
- `ops-service` 只读并只使用 Python 标准库。新增 endpoint 不得泄露 artifact URL、Settings、token、password、JWT、generated secret 或完整环境。

## 变更清单

- 修改端口/route：同步 `Dockerfile`、README、Nginx、Supervisor、entrypoint、healthcheck、smoke 与文档。
- 修改 Secret/Variable：更新 `.env.example`（只键名）、`hfs-dev.toml`、entrypoint、ops safe keys、配置/部署/runbook 文档和 ignore rules。
- 修改 MySQL/Redis/backup：保留容器本地 datadir、`/data/backups` 逻辑恢复语义；只能在隔离环境验证 restart/restore。
- 修改 artifact：保持 tag+digest、archive 名含 immutable ref、readback before manifest、manifest-only consumer、no fallback。

不要在仓库中新增真正的 `.env`、runtime config、archive、dump、cache、credential 或 `local/` 资料。