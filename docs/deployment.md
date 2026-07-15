# 部署指南

## Hugging Face Space 部署

### 前提

- Hugging Face 账号
- 新建 Space，SDK 选择 **Docker**
- 建议启用 Persistent Storage，用于保存 `/data`

### 步骤

1. 推送本仓库文件到 Space 仓库根目录：

```bash
git remote add hf https://huggingface.co/spaces/<username>/<space-name>
git push hf main
```

2. Space 会根据 `README.md` 顶部 YAML 识别：

```yaml
sdk: docker
app_port: 7860
```

3. 在 Space Settings 中建议：
   - Hardware: CPU Basic 或 CPU Upgrade
   - Storage: Persistent Storage（保留 MySQL、Redis、NocoDB 文件和生成 secret）

4. 在 Space Settings -> Variables 设置（可选）：
   - `NC_SITE_URL`（Space 公网 URL）
   - `NC_DEFAULT_LOCALE`（NocoDB UI 默认语言，默认 `zh-Hans`；支持 `en`、`zh-Hans`、`zh-Hant`）

5. 在 Space Settings -> Secrets 设置（可选，不设则自动生成）：
   - `MYSQL_ROOT_PASSWORD`
   - `MYSQL_PASSWORD`
   - `NC_AUTH_JWT_SECRET`
   - `OPS_TOKEN`（推荐设置，便于远程诊断）

如果没有设置这些 secret，入口脚本会在首次启动时生成并写入 `/data/config/generated.env`。这适合临时 demo，但远程调用 `/_ops/` 时不方便读取自动生成的 `OPS_TOKEN`，因此建议显式设置。

### 查看运行状态

```bash
# 健康检查（无需鉴权）
curl https://your-space.hf.space/healthz

# Ops 诊断（需 OPS_TOKEN）
curl -H "X-Ops-Token: $OPS_TOKEN" https://your-space.hf.space/_ops/status
```

`/healthz` 会检查 MySQL、Redis 和 NocoDB。Nginx 自身健康检查为 `/nginx-health`。

## 本地 Docker 部署

```bash
# 构建默认镜像 db-all-in-one-hfs:latest
scripts/build.sh

# 运行（交互模式，使用 named volume db-hfs-persist）
scripts/run-demo.sh

# 后台运行
# 先在当前 shell 中设置 OPS_TOKEN，再启动
docker run -d --name db-aio-hfs \
  -p 7860:7860 \
  -v db-hfs-data:/data \
  -e OPS_TOKEN="$OPS_TOKEN" \
  db-all-in-one-hfs:latest

# Smoke 测试
scripts/smoke.sh http://localhost:7860
```

`scripts/smoke.sh` 主要用于检查公开端点。需要验证 ops 鉴权端点时，使用下面的 `curl -H "X-Ops-Token: ..."` 命令单独检查。

`scripts/build.sh` 和 `scripts/run-demo.sh` 都支持把镜像 tag 作为第一个参数：

```bash
scripts/build.sh db-all-in-one-hfs:test
scripts/run-demo.sh db-all-in-one-hfs:test
```

Space build 无法依赖运行时变量补齐 Docker build pin，因此提交到 Space 的 Dockerfile 默认值本身必须是不可变候选。更新版本时使用完整的 tag/version + digest：

```bash
UBUNTU_VERSION='24.04@sha256:<digest>' \
MYSQL_SERVER_PACKAGE='mysql-server=<version>' \
MYSQL_CLIENT_PACKAGE='mysql-client=<version>' \
NOCODB_IMAGE_REF='nocodb/nocodb:<tag>@sha256:<digest>' \
scripts/build.sh db-all-in-one-hfs:<tag>
```

NocoDB `2026.06.1` 之后不再发布 standalone executable；部署构建从 pinned 官方 OCI image 复制 NocoDB runtime，不再访问 `Noco-linux-*` release asset。

## 读取本地自动生成的 OPS_TOKEN

如果使用 `scripts/run-demo.sh`，持久化卷名是 `db-hfs-persist`。可用同一镜像读取生成的 token：

```bash
docker run --rm --entrypoint bash \
  -v db-hfs-persist:/data \
  db-all-in-one-hfs:latest \
  -lc 'grep "^_GEN_OPS_TOKEN=" /data/config/generated.env'
```

拿到 token 后：

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" http://localhost:7860/_ops/status
```

## 数据备份与恢复边界

MySQL 数据存储在 `/data/mysql`。备份建议：

```bash
docker exec db-aio-hfs bash -lc '
  . /data/config/generated.env
  mysqldump --socket=/data/run/mysqld/mysqld.sock \
    -u root -p"$_GEN_MYSQL_ROOT_PASSWORD" \
    --all-databases
' > backup.sql
```

如果容器名来自 `scripts/run-demo.sh`，应使用 `db-aio-hfs-demo`。

恢复和长期备份策略不在本 demo 内自动处理。生产数据请使用独立 MySQL 服务和正式备份方案。

## 注意事项

- 本方案为 Demo/PoC 用途，不建议承载生产数据
- HF Spaces 免费层可能有资源限制和冷启动
- 密钥在首次启动时自动生成并持久化，挂载卷不丢失
- 改动 `MYSQL_VERSION`、MySQL package pin 或 `NOCODB_IMAGE_REF` 属于版本升级，需重新构建并单独验证兼容性
