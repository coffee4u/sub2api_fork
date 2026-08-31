# Sub2API Fork 交接文档

> 面向接手这个仓库、需要自行构建和部署的人。
> 编写日期：2026-08-31。基线提交 `c166da8f0`。

---

## 0. 三十秒版本

| 问题 | 答案 |
|---|---|
| 这个 fork 改了什么应用代码？ | **没有。** 两个本地提交只加了 `deploy/oracle-free-tier/` 一套 Oracle 双机部署脚本 |
| 想跑起来最快的路？ | Docker：`deploy/docker-compose.local.yml`，不需要装任何工具链 |
| 想自己编译？ | 用根目录 `Dockerfile`（工具链已固定好），别手工装 Go/Node |
| 官方文档能直接照抄吗？ | **不能。** 版本号和仓库地址都有错，见 §2 和 §6 |

---

## 1. 仓库定位

```
origin    https://github.com/coffee4u/sub2api_fork.git   ← 本仓库（公开）
upstream  https://github.com/Wei-Shaw/sub2api.git        ← 上游
```

**本 fork 相对上游的全部差异：**

| 提交 | 内容 |
|---|---|
| `42e621249` | 新增 `deploy/oracle-free-tier/`：Caddyfile、三个 compose 文件、README、oracle.env.example |
| `c166da8f0` | 新增 `deploy/oracle-free-tier/scripts/` 八个脚本；`.gitignore` 移除 `scripts` 忽略规则 |

**应用代码（`backend/`、`frontend/`）与上游完全一致，没有任何本地修改。**

⚠️ **当前落后上游 174 个提交**（领先 2 个）。上游最新为 `200602b41`。这意味着：

- 你构建出来的是上游 2026-08-31 之前的版本，不含之后的修复
- 如果要跟进上游，`git merge upstream/main` 会在 `.gitignore` 上冲突（见 §6.8）

⚠️ `origin` 是**公开仓库**。任何提交都会立刻对全网可见。

---

## 2. 工具链版本（第一个坑）

**以代码为准，不要相信 `README.md` 的 Prerequisites 章节。**

| 组件 | 真实要求 | 权威出处 | `README.md:479` 写的 |
|---|---|---|---|
| Go | **1.27.0**（精确版本） | `backend/go.mod:3`、`Dockerfile:11` | ❌ `1.21+` |
| Node.js | **24** | `Dockerfile:10` | ❌ `18+` |
| pnpm | **9**（固定） | `Dockerfile:29` `corepack prepare pnpm@9` | 未提及 |
| PostgreSQL | **18** | `Dockerfile:13`、`deploy/docker-compose.local.yml:223` | ❌ `15+` |
| Redis | **8** | `deploy/docker-compose.local.yml:254` | ❌ `7+` |
| Alpine（运行时） | 3.21 | `Dockerfile:12` | — |
| golangci-lint | v2.13 | `DEV_GUIDE.md` | — |

Go 版本是**硬断言**，不是下限：CI 三个 workflow 都执行 `go version | grep -q 'go1.27.0'`。装 1.21 或 1.28 都会失败。

`README.md:202` 的技术栈表格写的是 Go 1.27.0（正确），和同文件 `:479` 自相矛盾 —— 以 `go.mod` 为准。

---

## 3. 构建路线

### 路线 A：Docker 镜像（推荐）

工具链全部固定在 `Dockerfile` 里，本机**只需要 Docker + buildx**，不用装 Go / Node / pnpm。

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t sub2api:local \
  --build-arg VERSION=1.0.0 \
  -f Dockerfile .
```

镜像是四阶段构建：前端（node:24）→ 后端（golang:1.27.0，带 `-tags embed` 内嵌前端）→ pg 客户端 → alpine 运行时。

**如果要产出可离线搬运的归档**，用本 fork 提供的脚本（会自动 `docker save` + gzip）：

```bash
deploy/oracle-free-tier/scripts/01-build-image.sh
# 产物：deploy/oracle-free-tier/artifacts/sub2api-oracle-amd64.tar.gz
```

⚠️ 该脚本用 `git describe --tags --exact-match` 取版本号（因为 `.dockerignore` 排除了 `.git`，容器内取不到 tag）。**当前 commit 不在 tag 上时版本号为空**，需手动指定：

```bash
SUB2API_VERSION=1.2.3 deploy/oracle-free-tier/scripts/01-build-image.sh
```

对方机器上只需：`gzip -dc sub2api-oracle-amd64.tar.gz | docker load`

### 路线 B：源码编译

前置：Go 1.27.0、Node 24、pnpm 9（版本见 §2）。

```bash
# 注意：clone 本 fork，不是官方文档里的上游地址
git clone https://github.com/coffee4u/sub2api_fork.git
cd sub2api_fork

npm install -g pnpm@9

# 1. 编译前端（输出到 backend/internal/web/dist/）
cd frontend
pnpm install --frozen-lockfile
pnpm run build

# 2. 编译后端，内嵌前端
cd ../backend
VERSION="$(./scripts/resolve-version.sh)"
go build -tags embed -ldflags="-X main.Version=${VERSION}" -o sub2api ./cmd/server

# 3. 准备配置
cp ../deploy/config.example.yaml ./config.yaml
```

🔴 **`-tags embed` 不能省。** 少了它编译出的二进制不带前端界面，访问只有 API 没有 UI。

### 路线 C：Makefile（仅适合开发，不要用于发布）

```bash
make build          # = build-backend + build-frontend
make test           # 后端测试 + 前端 lint/typecheck/关键用例
```

🔴 **`make build-backend` 没有 `-tags embed`**（见 `backend/Makefile:7`），产出的 `backend/bin/server` **不含前端**。要发布请用路线 A 或 B。

---

## 4. 运行路线

### 4.1 单机 Docker Compose（上游方案，最简单）

```bash
cd deploy
cp .env.example .env
chmod 600 .env
# 必填 POSTGRES_PASSWORD；强烈建议固定 JWT_SECRET 和 TOTP_ENCRYPTION_KEY
JWT_SECRET=$(openssl rand -hex 32)
TOTP_ENCRYPTION_KEY=$(openssl rand -hex 32)

mkdir -p data postgres_data redis_data
docker compose -f docker-compose.local.yml up -d
docker compose -f docker-compose.local.yml logs -f sub2api   # 找自动生成的 admin 密码
# 访问 http://localhost:8080
```

⚠️ `docker-compose.local.yml:27` 用的镜像是 `weishaw/sub2api:latest` —— **这是上游发布的镜像，不是你构建的**。要用自己的构建产物，把 `image:` 改成你的本地 tag（例如 `sub2api:local`）。

`AUTO_SETUP=true` 时首次启动会自动建库、跑迁移、建管理员账号、写 config.yaml，不需要走 Setup Wizard。

完整选项见 `deploy/README.md`，但**注意该文档的已知错误**（§6.2）。

### 4.2 Oracle 双机部署（本 fork 新增）

两台 Oracle AMD 永久免费实例（各 1 GB 内存）：

- `sub2api-server`：只跑应用容器 + Caddy 反向代理
- `sub2api-db`：跑 PostgreSQL 18 + Redis 8

设计意图是**在本地构建镜像再上传**，避免在 1 GB 机器上编译。

```bash
cp deploy/oracle-free-tier/oracle.env.example deploy/oracle-free-tier/oracle.env
# 填写主机 IP、内网 IP、各类密码密钥（openssl rand -hex 32）

deploy/oracle-free-tier/scripts/01-build-image.sh      # 本地构建
deploy/oracle-free-tier/scripts/02-provision-hosts.sh  # 装 Docker、建 swap、防火墙
deploy/oracle-free-tier/scripts/03-deploy-db.sh        # 先部署数据库
deploy/oracle-free-tier/scripts/04-deploy-server.sh    # 再部署应用
deploy/oracle-free-tier/scripts/07-deploy-caddy.sh     # HTTPS 反代（自动签证书）

deploy/oracle-free-tier/scripts/05-status.sh           # 查状态
deploy/oracle-free-tier/scripts/06-logs.sh server|db|caddy   # 查日志
```

详见 `deploy/oracle-free-tier/README.md`，但**该文档有多处不准确**，见 §6。

**这套部署的资源上限**（1 GB 机器上的硬约束，接手后容易被它咬到）：

| 项 | 值 | 出处 |
|---|---|---|
| 应用容器硬内存上限 | 760 MB | `docker-compose.server.yml:6` |
| PostgreSQL / Redis 硬上限 | 520 MB / 220 MB | `docker-compose.db.yml:7,41` |
| 应用 `GOMEMLIMIT` | 512 MiB | `docker-compose.server.yml:18` |
| DB 连接池 | 6 / 2 | `docker-compose.server.yml:27-28` |
| **图片请求并发** | **1，超出直接拒绝** | `docker-compose.server.yml:46-50` |
| swap | 4 GB | `oracle.env` 的 `ORACLE_SWAP_SIZE_GB` |

图片并发被限成 1 且 `OVERFLOW_MODE=reject`，这是最容易被误判成"服务有 bug"的一项。并发流式请求多的场景请换 A1 ARM 或付费实例。

---

## 5. 需要额外交接的东西（不在仓库里）

以下内容**故意被 gitignore，必须走带外渠道**（加密传输，不要用 git / 邮件正文 / 即时通讯明文）：

| 内容 | 路径 | 说明 |
|---|---|---|
| 部署配置与全部机密 | `deploy/oracle-free-tier/oracle.env` | 含 DB / Redis / admin 密码、`JWT_SECRET`、`TOTP_ENCRYPTION_KEY`、真实主机 IP |
| SSH 私钥 | `keys_pub/ssh-key-sub2api-{server,db}.key` | 从 OCI 下载的实例登录私钥 |
| 单机部署配置 | `deploy/.env` | 同上类机密 |
| 镜像归档 | `deploy/oracle-free-tier/artifacts/` | 可重新构建，不必交接 |

**交接时建议直接轮换全部机密**，而不是移交现有值：`JWT_SECRET` 换掉会使所有登录态失效（预期行为），`TOTP_ENCRYPTION_KEY` 换掉会导致已绑定的 2FA 失效（需用户重新绑定，**换之前务必确认**）。

另需交接的非文件资产：OCI 账号权限、域名 DNS 控制权、Docker Hub 账号（如果要发布镜像）。

✅ 已核对：仓库**全历史从未提交过**任何 `.key` / `.pem` / `.env` 文件，脚本内也无硬编码机密、IP、域名或邮箱。

---

## 6. 已知问题清单

接手前请通读。按严重度排序。

### 6.1 🔴 远端 `.env` 权限是 644，机密全局可读

`deploy/oracle-free-tier/scripts/common.sh:115-123` 的 `write_env_file` 没有设权限。实测产物为 `-rw-r--r--`，`scp`（未加 `-p`）传到远端后仍是 `0644`。结果：`/opt/sub2api/{app,db,caddy}/.env` 里的 `POSTGRES_PASSWORD`、`REDIS_PASSWORD`、`ADMIN_PASSWORD`、`JWT_SECRET`、`TOTP_ENCRYPTION_KEY` **服务器上任何本地用户都能读**。

修复（改一处，三个部署脚本同时生效）：

```bash
write_env_file() {
  local dest="$1"
  shift
  : > "${dest}"
  chmod 600 "${dest}"        # ← 补这行
  ...
}
```

远端还需在 `scp` 之后补一次 `chmod 600 .env`（scp 不保留源权限）。

### 6.2 🔴 `deploy/README.md` 的所有 URL 指向上游

照着做会拿到**上游代码而非本 fork**：

| 位置 | 内容 |
|---|---|
| `deploy/README.md:59,62` | `curl .../Wei-Shaw/sub2api/main/deploy/docker-deploy.sh` |
| `deploy/README.md:95` | `git clone https://github.com/Wei-Shaw/sub2api.git` |
| `deploy/README.md:379` | `curl .../Wei-Shaw/sub2api/main/deploy/install.sh` |
| `README.md:487` | `git clone https://github.com/Wei-Shaw/sub2api.git` |

本文档 §3 已给出修正后的命令。

### 6.3 🟡 工具链版本文档错误

见 §2 表格。`README.md:479` 的 Prerequisites 全部偏低，按它装必然编译失败。

### 6.4 🟡 `make build` 产物不含前端

`backend/Makefile:7` 缺 `-tags embed`。见 §3 路线 C。

### 6.5 🟡 Oracle README 的网络规则会导致证书签发失败

`deploy/oracle-free-tier/README.md:44` 写"允许**需要访问的客户端**访问 80/443"。但 Caddy 走 ACME 自动签证书，Let's Encrypt 校验来自全球不固定 IP，**80/443 必须对 `0.0.0.0/0` 放通**，否则首签和续期都会失败。

### 6.6 🟡 Oracle README 与脚本对 8080 的说法矛盾

README `:49` 说"不要把 8080 对公网开放"，但 `02-provision-hosts.sh:168` 实际执行 `firewall-cmd --add-port=8080/tcp`。实际不构成暴露（应用只绑 `127.0.0.1:8080`，OCI 安全列表另有一层），但文档与行为不一致。

### 6.7 🟡 `CADDY_EMAIL` 默认值会被 Let's Encrypt 拒绝

`oracle.env.example:37` 默认 `admin@sub2api.local`。`.local` 域名邮箱无法完成 ACME 账号注册，**必须改成真实邮箱**。同理 `CADDY_DOMAIN` 必须是真实解析到应用主机的域名。

### 6.8 🟡 `.gitignore` 与上游冲突

本 fork 的 `c166da8f0` 删掉了上游的三行：

```
scripts
!backend/scripts/
!backend/scripts/resolve-version.sh
```

后果：下次 `git merge upstream/main` 必在 `.gitignore` 冲突；且现在**全仓库所有 `scripts/` 目录都不再被忽略**，别处放本地脚本容易误提交。建议改为保留上游规则 + 定向放行：

```
scripts
!backend/scripts/
!backend/scripts/resolve-version.sh
!deploy/oracle-free-tier/scripts/
!deploy/oracle-free-tier/scripts/**
```

### 6.9 🟡 部署脚本的三个安全习惯问题

- `02-provision-hosts.sh:138`：`curl -fsSL https://get.docker.com | sudo sh` —— 未固定版本的远程脚本以 root 执行。合规环境通常不允许；脚本对 Oracle Linux 已走发行版仓库，只有 fallback 分支是管道。
- `common.sh` 多处：`StrictHostKeyChecking=accept-new` —— 首次连接无条件信任主机指纹，有 MITM 窗口。建议预置 `known_hosts`。
- `04-deploy-server.sh:41`：镜像归档 `docker load` 后**未删除**，长期占盘（1 GB 实例上的磁盘很紧）。加 `rm -f` 即可。

### 6.10 ℹ️ `DEV_GUIDE.md` 的 fork 信息是别人的

`DEV_GUIDE.md` 来自上游（`73aabc861`，本地未修改），里面"Fork 仓库"写的是 `bayma888/sub2api-bmai`，**不是本仓库**；本地环境章节的 PostgreSQL 16 也与实际部署的 18 不一致。该文档的 CI / golangci-lint / Go 版本联动说明仍然有效且有参考价值，读时忽略仓库名和本地环境两节即可。

---

## 7. 接手验证清单

按顺序做完，能确认环境和构建链路都通：

```bash
# 1. 确认拿到的是本 fork
git remote -v                          # origin 应为 coffee4u/sub2api_fork
git log --oneline -2                   # 应见 c166da8f0 / 42e621249

# 2. 确认工具链（走路线 A 只需这一条）
docker buildx version

# 3. 构建
docker buildx build --platform linux/amd64 --load -t sub2api:local \
  --build-arg VERSION=0.0.0-dev -f Dockerfile .

# 4. 单机跑通
cd deploy && cp .env.example .env && chmod 600 .env
# 编辑 .env：设 POSTGRES_PASSWORD / JWT_SECRET / TOTP_ENCRYPTION_KEY
# 把 docker-compose.local.yml 的 image 改为 sub2api:local
mkdir -p data postgres_data redis_data
docker compose -f docker-compose.local.yml up -d
curl -fsS http://127.0.0.1:8080/health          # 应返回健康状态
docker compose -f docker-compose.local.yml logs sub2api | grep "admin password"

# 5.（可选）源码编译链路
make test                              # 后端测试 + 前端 lint/typecheck
```

跑到第 4 步 `/health` 有响应，就说明构建和运行链路完整，可以开始按 §4.2 做 Oracle 部署或按自己的需求改造。

---

## 8. 建议的接手后动作

优先级从高到低：

1. **修 §6.1 的 `chmod 600`** —— 这是唯一一条正在实际暴露机密的问题
2. **轮换全部机密**（见 §5 的 `TOTP_ENCRYPTION_KEY` 注意事项）
3. 修 §6.8 的 `.gitignore`，恢复与上游的兼容
4. 决定是否跟进上游 174 个提交；如果要，先处理 `.gitignore` 冲突
5. 修 §6.2 / §6.3 的文档错误，避免下一个人重复踩坑
6. 评估 `deploy/oracle-free-tier/` 是否应该留在公开仓库 —— 它不含机密，但完整披露了基础设施拓扑（远端路径、SSH 用户、密钥文件命名、端口布局、防火墙规则形状）
