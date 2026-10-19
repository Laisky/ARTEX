#!/usr/bin/env bash
# ARTEX 安装脚本：① 全部 Docker  ② 本地编译运行
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

info(){ printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[!]\033[0m %s\n' "$*"; }
die(){  printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ask(){  local p="$1" d="${2:-}" a; read -rp "$p${d:+ [$d]}: " a; echo "${a:-$d}"; }
rand(){ head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }

# ── docker 环境检测 / 自动安装 ───────────────────
ensure_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "已检测到 docker 与 docker compose"; return
  fi
  warn "未检测到 docker / docker compose"
  case "$(uname -s)" in
    Linux)
      if [ "$(ask '自动安装 Docker? (y/n)' y)" = y ]; then
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER" || true
        ok "Docker 安装完成（用户组变更需重新登录后免 sudo）"
      else
        die "请自行安装 docker 后重试"
      fi ;;
    Darwin) die "macOS 请安装 Docker Desktop：https://www.docker.com/products/docker-desktop/" ;;
    *)      die "请自行安装 docker 后重试" ;;
  esac
}

# ── ① 全部 Docker ───────────────────────────────
install_docker(){
  ensure_docker
  local pw key bind_ip
  if [ ! -f .env ]; then
    cp .env.example .env 2>/dev/null || true
    pw="$(ask 'Postgres 密码（回车随机生成）' "$(rand)")"
    bind_ip="$(ask 'Tailscale IPv4（tailscale ip -4）' "$(tailscale ip -4 2>/dev/null | head -n 1 || true)")"
    key="$(ask 'ANTHROPIC_API_KEY（可留空，后续在 UI 配）' '')"
    [ -n "$bind_ip" ] || die "未提供 Tailscale IPv4；请先运行 tailscale up"
    [ "$bind_ip" != "0.0.0.0" ] || die "ARTEX_BIND_IP 不能是 0.0.0.0"
    sed -i.bak "s|^ARTEX_BIND_IP=.*|ARTEX_BIND_IP=${bind_ip}|" .env
    sed -i.bak "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pw}|" .env
    sed -i.bak "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${key}|" .env
    rm -f .env.bak
    chmod 600 .env
    ok "已生成 .env（Tailscale 地址与 POSTGRES_PASSWORD 已设置）"
  else
    info "沿用已存在的 .env"
    pw="$(sed -n 's/^POSTGRES_PASSWORD=//p' .env | tail -n 1)"
    bind_ip="$(sed -n 's/^ARTEX_BIND_IP=//p' .env | tail -n 1)"
    if [ -z "$bind_ip" ]; then
      bind_ip="$(ask 'Tailscale IPv4（tailscale ip -4）' "$(tailscale ip -4 2>/dev/null | head -n 1 || true)")"
      [ -n "$bind_ip" ] || die "未提供 Tailscale IPv4；请先运行 tailscale up"
      [ "$bind_ip" != "0.0.0.0" ] || die "ARTEX_BIND_IP 不能是 0.0.0.0"
      printf '\nARTEX_BIND_IP=%s\n' "$bind_ip" >> .env
      ok "已补充 .env 的 ARTEX_BIND_IP"
    fi
  fi

  [ -n "$pw" ] || die "未找到 POSTGRES_PASSWORD；请检查 .env"
  [ -n "$bind_ip" ] || die "未找到 ARTEX_BIND_IP；请检查 .env"

  if [ ! -f config.json ]; then
    cat > config.json <<JSON
{
  "database": {
    "host": "postgres",
    "port": 5432,
    "user": "artex",
    "password": "${pw}",
    "dbname": "artex_local",
    "sslmode": "disable"
  },
  "skill_dir": "/app/skills"
}
JSON
    chmod 600 config.json
    ok "已生成容器模式 config.json"
  else
    info "沿用已存在的 config.json；请确认 database.host 为 postgres"
  fi

  if [ ! -s jwt.key ]; then
    openssl rand -hex 32 > jwt.key
    chmod 600 jwt.key
    ok "已生成持久化 jwt.key"
  fi

  docker volume create artex-local-pgdata >/dev/null
  info "从当前源码构建并启动…"
  docker compose build artex
  docker compose up -d
  ok "启动完成 → http://${bind_ip}:8787"
  info "查看日志：docker compose logs -f artex"
}

# ── ② 本地编译运行 ──────────────────────────────
install_local(){
  echo "数据库安装方式："
  echo "  1) 连接已有 PostgreSQL"
  echo "  2) 用 Docker 起一个 PostgreSQL（需要 docker）"
  case "$(ask '选择' 1)" in
    2)
      ensure_docker
      local pw; pw="$(ask 'Postgres 密码（回车随机）' "$(rand)")"
      docker run -d --name artex-pg -p 5432:5432 \
        -e POSTGRES_USER=artex -e POSTGRES_PASSWORD="$pw" -e POSTGRES_DB=artex \
        -v artex-pg:/var/lib/postgresql/data postgres:16-alpine
      DB_HOST=127.0.0.1 DB_PORT=5432 DB_USER=artex DB_PASS="$pw" DB_NAME=artex DB_SSL=disable ;;
    *)
      DB_HOST="$(ask '数据库地址' 127.0.0.1)"
      DB_PORT="$(ask '端口' 5432)"
      DB_USER="$(ask '账号' artex)"
      DB_PASS="$(ask '密码' '')"
      DB_NAME="$(ask '数据库名' artex)"
      DB_SSL="$(ask 'sslmode (disable/require)' disable)" ;;
  esac

  # 生成 config.json
  cat > config.json <<JSON
{
  "database": {
    "host": "${DB_HOST}",
    "port": ${DB_PORT},
    "user": "${DB_USER}",
    "password": "${DB_PASS}",
    "dbname": "${DB_NAME}",
    "sslmode": "${DB_SSL}"
  }
}
JSON
  ok "已生成 config.json"

  # go 环境检查
  command -v go >/dev/null 2>&1 || die "未检测到 Go，请先安装 Go（>=1.26）：https://go.dev/dl/"
  ok "Go: $(go version)"

  # 内嵌前端需要 node 出静态产物
  if command -v npm >/dev/null 2>&1; then
    info "构建前端静态产物…"
    ( cd web && npm ci && npm run build:static )
    rm -rf server/webui/dist && cp -r web/out server/webui/dist
    info "编译内嵌单二进制…"
    CGO_ENABLED=0 go build -tags embedui -trimpath -o artex ./cmd/artex
  else
    warn "未检测到 npm：将编译**不内嵌前端**的后端（前端需另跑 npm run dev）"
    CGO_ENABLED=0 go build -o artex ./cmd/artex
  fi
  ok "编译完成 → ./artex"

  info "启动…（Ctrl-C 退出）"
  ./artex
}

echo "=============================="
echo "  ARTEX 安装"
echo "  1) 全部 Docker 安装"
echo "  2) 本地运行（go 编译）"
echo "=============================="
case "$(ask '选择' 1)" in
  1) install_docker ;;
  2) install_local ;;
  *) die "无效选择" ;;
esac
