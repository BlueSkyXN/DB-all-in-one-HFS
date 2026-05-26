# 部署指南

## Hugging Face Space 部署

### 前提

- Hugging Face 账号
- 新建 Space，SDK 选择 **Docker**

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
   - Storage: Persistent Storage（保留数据库数据）

4. 在 Space Settings → Variables 设置（可选）：
   - `NC_SITE_URL`（Space 公网 URL）

5. 在 Space Settings → Secrets 设置（可选，不设则自动生成）：
   - `MYSQL_ROOT_PASSWORD`
   - `MYSQL_PASSWORD`
   - `NC_AUTH_JWT_SECRET`
   - `OPS_TOKEN`（推荐设置，便于远程诊断）

### 查看运行状态

```bash
# 健康检查（无需鉴权）
curl https://your-space.hf.space/healthz

# Ops 诊断（需 OPS_TOKEN）
curl -H "X-Ops-Token: $OPS_TOKEN" https://your-space.hf.space/_ops/status
```

## 本地 Docker 部署

```bash
# 构建
scripts/build.sh

# 运行（交互模式）
scripts/run-demo.sh

# 后台运行
docker run -d --name db-aio-hfs \
  -p 7860:7860 \
  -v db-hfs-data:/data \
  -e OPS_TOKEN=my_secret_token \
  db-all-in-one-hfs:latest

# Smoke 测试
scripts/smoke.sh http://localhost:7860
```

如需固定不同的 NocoDB 版本，可在构建时传入 build arg：

```bash
docker build --build-arg NOCODB_VERSION=0.301.3 -t db-all-in-one-hfs:latest .
```

## 数据备份

MySQL 数据存储在 `/data/mysql`。备份建议：

```bash
# 进入容器执行 mysqldump
docker exec db-aio-hfs mysqldump \
  --socket=/data/run/mysqld/mysqld.sock \
  -u root -p"$MYSQL_ROOT_PASSWORD" \
  --all-databases > backup.sql
```

## 注意事项

- 本方案为 Demo/PoC 用途，不建议承载生产数据
- HF Spaces 免费层可能有资源限制和冷启动
- 密钥在首次启动时自动生成并持久化，挂载卷不丢失
