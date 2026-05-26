---
title: DB-all-in-one-HFS
emoji: 🗄️
colorFrom: blue
colorTo: purple
sdk: docker
app_port: 7860
pinned: false
---

# DB-all-in-one-HFS

基于 **MySQL 9.7 LTS** + **NocoDB** 的一体化数据库管理服务，适用于 Hugging Face Spaces 部署。

NocoDB 提供类 Airtable 的可视化界面，底层使用 MySQL 9.7 LTS 作为持久化存储引擎。

## 功能特性

- 🗄️ MySQL 9.7 LTS 长期支持版（支持至 2031 年）
- 📊 NocoDB 可视化数据库管理（表格视图、看板、表单、画廊等）
- 🔐 JWT 认证 + 用户权限管理
- 📡 REST API & GraphQL 自动生成
- 🐳 单容器运行，开箱即用

## 本地运行

```bash
docker build -t db-all-in-one-hfs .
docker run --rm -p 7860:7860 \
  -e MYSQL_ROOT_PASSWORD=your_root_pwd \
  -e MYSQL_PASSWORD=your_nocodb_pwd \
  -e NC_AUTH_JWT_SECRET=your_jwt_secret \
  -v db_data:/data \
  db-all-in-one-hfs
```

启动后访问：

- NocoDB UI: `http://localhost:7860`
- 健康检查: `http://localhost:7860/api/v1/health`

## Hugging Face Spaces 部署

1. 新建 Space，选择 `Docker` SDK。
2. 推送本目录文件到 Space 仓库。
3. 在 Space Settings → Secrets 中设置：
   - `MYSQL_ROOT_PASSWORD`
   - `MYSQL_PASSWORD`
   - `NC_AUTH_JWT_SECRET`
4. Space 自动构建镜像并启动服务。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_ROOT_PASSWORD` | `nocodb_root_pwd` | MySQL root 密码 |
| `MYSQL_DATABASE` | `nocodb` | 默认数据库名 |
| `MYSQL_USER` | `nocodb` | NocoDB 使用的 MySQL 用户名 |
| `MYSQL_PASSWORD` | `nocodb_pwd` | NocoDB 使用的 MySQL 密码 |
| `NC_AUTH_JWT_SECRET` | `change_me_to_a_random_string` | JWT 签名密钥 |
| `NC_PORT` | `7860` | NocoDB 服务端口 |
| `NC_PUBLIC_URL` | (空) | 公网访问 URL |
| `NC_DISABLE_TELE` | `true` | 禁用遥测数据收集 |
| `DATA_DIR` | `/data` | 持久化数据根目录 |

## 架构说明

```
┌─────────────────────────────────────────┐
│           Docker Container              │
│                                         │
│  ┌─────────────┐    ┌───────────────┐  │
│  │  MySQL 9.7  │◄───│    NocoDB     │  │
│  │  LTS (3306) │    │  (port 7860)  │  │
│  └──────┬──────┘    └───────┬───────┘  │
│         │                   │           │
│         ▼                   ▼           │
│    /data/mysql        /data/nocodb      │
│                                         │
└─────────────────────────────────────────┘
           │
           ▼ EXPOSE 7860
      用户浏览器 / API 客户端
```

## 数据持久化

所有数据存储在 `/data` 卷下：

- `/data/mysql` — MySQL 数据文件
- `/data/nocodb` — NocoDB 元数据和上传文件

建议挂载持久卷以防止数据丢失：

```bash
docker run -v my_db_data:/data ...
```

## 安全建议

⚠️ **生产部署前请务必修改以下默认值：**

1. 设置强密码（`MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD`）
2. 设置随机 JWT 密钥（`NC_AUTH_JWT_SECRET`）
3. MySQL 仅绑定 `127.0.0.1`，不暴露到外部

## 许可证

GPL-3.0 — 详见 [LICENSE](./LICENSE)
