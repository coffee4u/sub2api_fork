# Oracle 甲骨文永久免费 AMD 实例部署

本目录用于把 Sub2API 部署到两台 Oracle AMD 永久免费小实例上：

- `sub2api-server`：只跑 Sub2API 应用容器。
- `sub2api-db`：跑 PostgreSQL 和 Redis。

脚本在本地构建应用镜像，上传到应用主机，然后用各自独立的 Compose 文件分别启动两边。这样做是为了避免在 1 GB 内存的实例上编译。

## 1. 准备配置

复制示例文件：

```bash
cp deploy/oracle-free-tier/oracle.env.example deploy/oracle-free-tier/oracle.env
```

需要填写以下值：

- `ORACLE_APP_HOST`：`sub2api-server` 的公网 IP 或域名。
- `ORACLE_DB_HOST`：`sub2api-db` 的公网 IP 或域名。
- `ORACLE_APP_PRIVATE_IP`：`sub2api-server` 的 VCN 内网 IP。
- `ORACLE_DB_PRIVATE_IP`：`sub2api-db` 的 VCN 内网 IP。
- `ADMIN_PASSWORD`、`POSTGRES_PASSWORD`、`REDIS_PASSWORD`。
- `JWT_SECRET`、`TOTP_ENCRYPTION_KEY`。

用下面的命令生成密钥值：

```bash
openssl rand -hex 32
```

SSH 私钥的默认路径与当前仓库检出保持一致：

```text
keys_pub/ssh-key-sub2api-server.key
keys_pub/ssh-key-sub2api-db.key
```

## 2. OCI 网络规则

在 OCI 的安全列表（Security List）或网络安全组（NSG）中配置：

- 应用实例公网入站：允许来自你自己 IP 的 `22/tcp`，以及允许需要访问 Sub2API 的客户端访问 `80/tcp` 和 `443/tcp`。
- 数据库实例公网入站：仅允许来自你自己 IP 的 `22/tcp`。
- 数据库实例内网入站：允许来自 `ORACLE_APP_PRIVATE_IP` 的 `5432/tcp` 和 `6379/tcp`。

不要把 PostgreSQL 或 Redis 暴露到 `0.0.0.0/0`。
部署完 Caddy 后，不要把应用端口 `8080/tcp` 对公网开放；应用绑定在 `127.0.0.1:8080`，公网 HTTP/HTTPS 由 Caddy 负责。

## 3. 本地构建

```bash
deploy/oracle-free-tier/scripts/01-build-image.sh
```

产出文件：

```text
deploy/oracle-free-tier/artifacts/sub2api-oracle-amd64.tar.gz
```

## 4. 初始化主机

```bash
deploy/oracle-free-tier/scripts/02-provision-hosts.sh
```

该脚本会在缺少 Docker 时安装 Docker、创建 4 GB swap 文件、创建远端部署目录，并在 firewalld 处于运行状态时应用 firewalld 规则。swap 大小由 `oracle.env` 里的 `ORACLE_SWAP_SIZE_GB` 控制。

## 5. 先部署数据库

```bash
deploy/oracle-free-tier/scripts/03-deploy-db.sh
```

## 6. 再部署应用

```bash
deploy/oracle-free-tier/scripts/04-deploy-server.sh
```

## 7. 部署 HTTPS 反向代理

在 `oracle.env` 中设置这两个值：

```text
CADDY_DOMAIN=sub2api.example.com
CADDY_EMAIL=admin@example.com
```

域名必须解析到 `ORACLE_APP_HOST`。如果使用 Cloudflare，加一条指向应用公网 IP 的 `A` 记录，并在 OCI 放通 `80/tcp` 和 `443/tcp`。

```bash
deploy/oracle-free-tier/scripts/07-deploy-caddy.sh
```

然后访问：

```text
https://CADDY_DOMAIN
```

## 8. 查看状态与日志

```bash
deploy/oracle-free-tier/scripts/05-status.sh
deploy/oracle-free-tier/scripts/06-logs.sh server
deploy/oracle-free-tier/scripts/06-logs.sh db
deploy/oracle-free-tier/scripts/06-logs.sh caddy
```

## 1 GB 实例注意事项

Compose 文件刻意采用了较小的连接池和内存限制：

- 应用 `GOMEMLIMIT=512MiB`
- 应用数据库连接池 `6/2`
- Redis 连接池 `20/2`
- PostgreSQL `max_connections=40`、`shared_buffers=128MB`
- Redis `maxmemory=128mb`

这套配置适合轻量测试。如果有较多并发的长流式请求，请改用 Oracle A1 ARM 免费实例或付费实例。
