# ARTEX：dev 主机部署与维护

本机 ARTEX 的唯一管理入口是 `/home/laisky/repo/laisky/VPS/dev-docker-compose.yml`。
所有服务直接定义在该文件中，不使用 include、import 或 extends，也不依赖 ARTEX
仓库的 Compose 或 `.env`。ARTEX checkout 仅提供构建源码、Dockerfile 和 skills。

## 1. 当前拓扑

| 项目 | 当前配置 |
|---|---|
| Compose project | `vps` |
| ARTEX 服务 / 容器 | `artex` / `vps-artex-1` |
| ARTEX 专属数据库服务 / 容器 | `postgres` / `vps-postgres-1` |
| 应用镜像 | 本地源码构建 `artex-local:local` |
| 数据库镜像 | `postgres:16-alpine` |
| 外部数据库卷 | `artex-local-pgdata` |
| ARTEX 专属网络 | `vps_artex` |
| HTTP 地址 | `http://100.75.198.70:8787` |
| 流量代理地址 | `http://100.75.198.70:8788` |
| 模型上游 | `https://oneapi.laisky.com/v1` |

VPS Compose 中的 `postgre` 是另一套数据库；它的存储、环境文件和端口保持原配置。
ARTEX 的 PostgreSQL 不发布宿主机端口，应用端口只绑定本机 Tailscale IPv4。

## 2. 配置、凭据与数据位置

| 宿主机位置 | 用途 / 容器位置 |
|---|---|
| `/opt/configs/env/dev/artex.env` | 仅模型环境变量及 API Key，通过服务 env_file 注入 |
| `/opt/configs/env/dev/artex-postgres.env` | 仅 PostgreSQL 初始化变量及密码，注入数据库容器 |
| `/opt/configs/artex/dev/config.json` | 数据库连接与 skills 路径，挂载 `/app/config.json`，只读 |
| `/opt/configs/artex/dev/jwt.key` | JWT 签名密钥，挂载 `/app/jwt.key`，只读 |
| `/opt/configs/artex/dev/admin-password` | 管理员密码，仅供宿主机操作员使用，不挂载 |
| `/opt/configs/artex/dev/pg-password` | 原部署保存的数据库密码副本，不挂载 |
| `/opt/configs/artex/dev/data/` | 会话、流量、工作文件及 CA 等，挂载 `/app/data` |
| `/opt/configs/artex/dev/backups/` | 数据库、敏感文件备份和迁移回执，不挂载 |
| Docker 卷 `artex-local-pgdata` | PostgreSQL 数据，挂载 `/var/lib/postgresql/data` |
| ARTEX checkout 的 `skills/` | 技能源码，挂载 `/app/skills` |

私有配置目录为 `0700`，凭据文件为 `0600`；运行期 data 的目录和文件由应用管理，
其父目录保持 `0700`。这些 ARTEX 私有路径已写入 `/opt/configs/.git/info/exclude`，
不会作为 configs 仓库的新文件自动出现在 Git 中。不要将环境文件、密码或备份加入 Git。

环境文件使用 Compose 的 `format: raw`，按 `KEY=原始值` 保存，不给值额外加引号；
其中的 `$` 不参与 Compose 插值。不要把完整 `docker compose config` 或容器 inspect
输出粘贴到日志、工单或聊天中，因为展开后包含密钥。

应用 env 文件包含 `OPENAI_API_KEY`、`ARTEX_LLM_PROVIDER`、`ARTEX_LLM_MODEL`、
`ARTEX_LLM_BASE_URL` 等，provider 当前为 `openai`，API Base 为
`https://oneapi.laisky.com/v1`。已保存到数据库中的模型配置优先于环境变量；如 UI
已配置模型，需要同步修改 UI。不要在应用环境中注入 PostgreSQL 初始化密码。

`config.json` 的数据库 host 保持 `postgres`；数据库密码须与数据库当前角色密码一致。
修改 env 文件的 `POSTGRES_PASSWORD` 不会自动轮换已有数据库卷中的角色密码。

## 3. 日常管理

以下命令从 VPS 目录执行：

```bash
cd /home/laisky/repo/laisky/VPS
docker compose -p vps -f dev-docker-compose.yml ps
docker compose -p vps -f dev-docker-compose.yml logs --tail=100 artex
```

修改 `/opt/configs/env/dev/artex.env` 后重新创建应用容器：

```bash
docker compose -p vps -f dev-docker-compose.yml up -d --no-deps --force-recreate artex
```

修改应用源码后构建并更新应用：

```bash
docker compose -p vps -f dev-docker-compose.yml build artex
docker compose -p vps -f dev-docker-compose.yml up -d --no-deps artex
```

停止或恢复 ARTEX：

```bash
docker compose -p vps -f dev-docker-compose.yml stop artex postgres
docker compose -p vps -f dev-docker-compose.yml up -d postgres artex
```

所有服务统一维护时直接使用此 dev Compose；只维护 ARTEX 时显式指定服务，避免重启其它服务。
不要再运行 ARTEX checkout 的独立 Compose 或安装/更新脚本来管理这台 dev 主机，
不要让另一个 PostgreSQL 进程同时使用同一数据库卷。

## 4. 登录与验收

管理员用户名为 `ARTEX`。密码存放在上面的私有文件中；不要输出到终端或提交到 Git。
保持 JWT 密钥不变可保留现有登录会话。首次设置密码的接口只用于全新数据库，
当前已初始化的实例不要重新初始化。

```bash
curl --noproxy '*' --fail --silent --show-error http://100.75.198.70:8787/api/health
curl --noproxy '*' --fail --silent --show-error http://100.75.198.70:8787/api/auth/status
```

两个容器应为 healthy，管理员状态为 initialized:true。迁移验收还要检查旧 JWT、
管理员密码、数据库计数、镜像 ID 和凭据内容是否保持一致。

## 5. 备份与恢复

从 VPS 目录执行，备份文件保持私有权限：

```bash
umask 077
backup_dir="/opt/configs/artex/dev/backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
docker compose -p vps -f dev-docker-compose.yml exec -T postgres sh -lc \
  'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup_dir/database.dump"
tar -czf "$backup_dir/files.tgz" -C /opt/configs \
  env/dev/artex.env env/dev/artex-postgres.env \
  artex/dev/config.json artex/dev/jwt.key artex/dev/admin-password artex/dev/pg-password artex/dev/data
```

一致性备份应先停止应用写入，完成后恢复应用。数据库恢复前停止应用，使用匹配的
数据库与文件备份，恢复后重新验证登录和数据。不要覆盖 JWT 密钥或删除数据库卷来排查故障。

数据库卷是 external，Compose down 不会删除它；`docker volume rm artex-local-pgdata`
才会显式销毁数据库数据。文件备份不要包含 backups 自身，以免递归打包。

## 6. 已知验证边界

模型环境变量已加载，但容器健康检查和登录成功不能证明 Agent 的本机隐私安全，
也不能代替 OneAPI 推理或授权靶场端到端验收。运行任务会把相关内容发送给模型服务。
仍需避免接入个人浏览器、个人凭证目录、Docker socket 或不可信 MCP。

迁移与验证回执保存在 `/opt/configs/artex/dev/backups/`。此前保存在用户目录下的
ARTEX 私有密码和迁移备份一并迁入该目录树，源码仓库不再保留真实运行凭据或工作数据。
