# 部署指南

本指南定义 HFS v2.1 Preview artifact 交付合同。Preview 日常变更可直接更新 canonical Space；任何 Secret 必须先写入 ignored plaintext `.env`，远端只保存部署副本并在写后 readback。candidate profile 仅用于高风险可选验证，使用 `local/hfs-targets/candidate.env`。该 demo 不适合生产数据；bucket、挂载、数据库或备份等有状态写操作仍需单独批准。

## 交付前 owner gates

在任何远端发布前，release owner 与 data owner 必须重新只读确认：

1. GitHub main/候选 tag 的完整 SHA、当前 Space wrapper ref 和预 artifact 回退锚点；不要把历史盘点当成当前事实。
2. Space 的实际 `/data` mount、可写性、现有数据库恢复点及 RPO/RTO。
3. `hfs-dist` 下载权限与无凭据 HTTPS manifest URL；下载面不能和 `/data` 挂载面混用。
4. 候选 Space/隔离 data target、NocoDB UI/API、MySQL/Redis/Nginx health、受控 restart、逻辑备份和隔离 restore 的验收窗口。

未经独立批准，不得 reset `/data`、恢复真实数据库、删除旧 archive/backup、prune Settings、替换 mount、restart/factory reboot 或清理 Space/bucket。

## 发布 artifact

`.github/workflows/publish-nocodb-artifact.yml` 只接受手动 `workflow_dispatch`。操作者必须输入 `PUBLISH_NOCODB_ARTIFACT`，并显式选择 `edge` 或 `release`：

1. workflow 读取 Dockerfile 中审计过的 `NOCODB_SOURCE_REF`（tag + digest），从该不可变 OCI ref 导出 rootfs archive。
2. archive 名包含上游 tag 和完整 wrapper commit；`release` 还要求远端 annotated Git tag peel 后指向当前 commit，并将同一字节 archive 上传到对应 GitHub Release。
3. artifact 写入 `hfs-dist/db-all-in-one-hfs/<slot>/` 后立即读回并校验 SHA-256。
4. 仅在 artifact readback 成功后写 `manifest.json`，随后读回逐字节比对。这是 manifest-last；失败不会扫描或回退。

`release` 的首次 GitHub/Hugging Face 写入紧前会重新 fetch `origin/main`，并把精确远端 `release_tag` fetch 到独立临时 ref。workflow 要求 ref 为 `refs/heads/main`，checkout `HEAD`、`GITHUB_SHA`、current main 与该 annotated tag peel 后的 commit 全部一致；lightweight tag 会失败关闭。`edge` 仍保留原有独立发布语义，不要求 release tag。

workflow 需要预先由 owner 配置的 `HF_TOKEN` Secret、`HFS_BUCKET_NAMESPACE` 与 `HFS_DIST_BASE_URL` Variables。它们不在 Git、`hfs-dev.toml` 或 `.env.example` 中保存值。workflow 未安装依赖；缺少 runner 上的 `hf`/`gh` CLI 时会失败关闭。

`edge` 只表示当前批准的 main 构建；`release` 指向批准的 GitHub Release。回退必须从 GitHub Release 的精确 archive 重新完成 artifact-readback/manifest-last，而不是复用旧目录扫描、直接 OCI COPY 或重置数据库。

## 部署 wrapper

`.github/workflows/deploy-hf-space.yml` 同样只能手动运行，并要求输入 `DEPLOY_DB_AIO_HFS`。它：

1. 拒绝未提交工作区，导出只含 Dockerfile、Space card、manifest、`.dockerignore`、`docker/` runtime contract 和生成的 `BUILD_SOURCE.json` 的 wrapper bundle。
2. candidate 与 primary 目标都必须已经是 Protected；primary 还必须由 manifest 精确选择 `BlueSkyXN/db-all-in-one-hfs`，并在上传紧前重新 fetch `origin/main`，确认 workflow ref、checkout `HEAD`、`GITHUB_SHA` 与 current main 完全一致。
3. 使用 HF CLI 上传该 bundle，不使用 credential-bearing Git URL、`git push`、force-push 或 whole-repository delete。
4. 下载并逐字节核对 `BUILD_SOURCE.json`、Dockerfile、manifest、ignore 规则和关键 bootstrap 文件；缺完整 40 位 wrapper SHA 即失败。

上传完成不代表 Space 已就绪。保持现有实例和数据不变，等待 owner 在批准的窗口中读取 Space revision/runtime provenance、`/healthz`、认证后的 `/_ops/provenance` 和业务 smoke。不要让 workflow 自动 restart 或恢复数据。

## Space Settings

先按 [配置参考](./configuration.md) 仅设置登记键名：

- Variables：`NC_SITE_URL`、`NC_DEFAULT_LOCALE`、`NOCODB_ARTIFACT_MANIFEST_URL`、`NOCODB_ARTIFACT_SLOT`。
- Secrets：`NOCODB_ARTIFACT_DOWNLOAD_TOKEN`、`MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD`、`NC_AUTH_JWT_SECRET`、`OPS_TOKEN`。

发布后 Space 启动必须由 manifest 驱动。缺少 `NOCODB_ARTIFACT_MANIFEST_URL`、slot 不匹配、下载失败、SHA/size/source ref/wrapper SHA/rootfs layout 任一不匹配都会退出，且发生在 MySQL 初始化和 `/data` 写入之前。

## 本地验证

```bash
scripts/static-check.sh
scripts/build.sh
NOCODB_ARTIFACT_MANIFEST_URL='https://<approved-dist-host>/db-all-in-one-hfs/release/manifest.json' \
NOCODB_ARTIFACT_SLOT='release' \
NOCODB_ARTIFACT_DOWNLOAD_TOKEN='<private-bucket-read-token>' \
scripts/run-demo.sh
scripts/smoke.sh http://localhost:7860
```

Docker build、`run-demo` 和 smoke 可能下载网络资源、启动容器、替换同名容器或接触 named volume；只应在隔离环境中执行。`run-demo` 会在 manifest URL 格式或 slot 无效时于删除现有 demo container 前停止，但不会预先访问远端验证一个格式正确的 manifest；已有 `/data` volume 不会被脚本删除。

## 备份和恢复边界

MySQL backup sidecar 每 `MYSQL_BACKUP_INTERVAL` 秒在 `/data/backups` 创建 `nocodb-*.sql.gz`，每份执行 `gzip -t`，保留 `MYSQL_BACKUP_KEEP` 份；启动从新到旧尝试恢复。这个逻辑恢复链不替代生产备份、异地归档或 PITR。验证恢复只可在隔离目标上进行，并由 data owner 明确批准。
