# ARTEX Local Setup Manual

## Purpose and verification status

This manual covers building ARTEX from source, starting a fresh local idle instance, checking its UI/API, stopping it, and retaining its data.

Repository: **Laisky/ARTEX**  
Pinned revision: [5c0dbd4bec940f3c0faf20705a56d879b57d3dfe](https://github.com/Laisky/ARTEX/commit/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe)

**Source-reviewed only, not run-tested.** No installation, build, startup, or health-check result is claimed here. The commands below target Bash on Linux/macOS; native Windows instructions are not verified.

Scope: local isolated study and idle-instance checks only. Do not create targets, scans, or testing tasks; configure model credentials, remote MCPs, or asset synchronization; or import production data. Read the repository's [LICENSE](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/LICENSE) and [README usage restrictions](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/README.md) first.

## 1. Prerequisites and chosen deployment route

Use a local PostgreSQL installation plus a source-built binary with the frontend embedded:

- Git
- Go 1.26.3 or a version satisfying the module's requirements; use `go.mod` as the authority
- Node.js 22 and its accompanying npm, matching the release workflow's major version
- PostgreSQL 16 as a reference version; the repository Compose file uses `postgres:16-alpine`
- rsync for copying generated frontend contents accurately
- A regular local OS user and a separate writable working directory; the application does not require root for these ports

Install prerequisites from their official distribution channels using the normal process for your OS. This guide does not install a package manager, Docker daemon, or privileged system service.

Dependency installation/building can contact package registries and execute npm lifecycle scripts. This is **not an offline build**. The pinned source requires `github.com/Autumn-27/norma v0.4.3`; its current download availability has not been tested. If a dependency is unavailable, record the exact package/version and redacted error. Do not substitute untrusted archives/scripts or disable dependency verification.

Sources: [go.mod](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/go.mod), [release workflow](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/.github/workflows/release.yml), [Compose](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/docker-compose.yml)

## 2. Obtain and pin a fresh checkout

Choose a new directory name that does not already contain an installation:

```bash
git clone https://github.com/Laisky/ARTEX.git ARTEX-local-study
cd ARTEX-local-study
git checkout --detach 5c0dbd4bec940f3c0faf20705a56d879b57d3dfe
git rev-parse HEAD
git status --short

go version
node --version
npm --version
psql --version
```

Record the actual versions. Pinning the source does not pin every system package, toolchain, or remotely downloaded artifact.

## 3. Prepare a genuinely new database

Under an existing local PostgreSQL administrator identity, create a dedicated non-superuser role and empty database:

```bash
createuser --pwprompt artex_study
createdb --owner=artex_study artex_study
```

The administrator login method depends on how PostgreSQL was installed. These are PostgreSQL administration commands, not commands to run blindly under the application account. If either name already exists, choose new names and update every subsequent example; do not reuse or overwrite an existing instance.

Enter the new database password interactively on your own machine. Do not place it in public documentation, command arguments, or Git. The application role needs access to its dedicated database and permission to create/manage the application's objects there; do not grant it superuser privileges.

Verify the actual local database port. The remaining examples use `127.0.0.1:5432`:

```bash
pg_isready -h 127.0.0.1 -p 5432
psql -h 127.0.0.1 -p 5432 -U artex_study -d artex_study -W \
  -c 'select current_database(), current_user;'
```

Do not restore an old ARTEX database. Startup applies schema changes and seeds built-in configuration, so it is not a read-only database connection. Precreating the database avoids depending on the application role's CREATEDB permission.

Source: [database initialization](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/db/db.go)

## 4. Create the local configuration

Create `config.json` in the checkout root and replace the password placeholder locally:

```json
{
  "database": {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "artex_study",
    "password": "<fill in locally>",
    "dbname": "artex_study",
    "sslmode": "disable"
  },
  "skill_dir": "./skills"
}
```

The `sslmode` example is restricted to this local loopback database connection, not a remote database. Do not blindly copy the sample file's port `5433` or skill path `/opt/artex/skills`; match your actual setup.

Configuration precedence:

1. `ARTEX_PG_DSN` overrides database configuration in the file
2. A nonempty `database.dsn` overrides separate database fields
3. `ARTEX_CONFIG` explicitly selects the configuration file
4. `ARTEX_SKILL_DIR` overrides `skill_dir`

Keep `config.json`, `jwt.key`, credentials, database backups, and sensitive log contents out of Git and public comments.

Sources: [configuration example](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/config.example.json), [configuration resolution](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/config/config.go), [.gitignore](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/.gitignore)

## 5. Build the embedded-UI binary

Build the real local UI with mock mode unset:

```bash
unset NEXT_PUBLIC_MOCK NEXT_PUBLIC_SSE_BASE

(
  cd web
  npm ci
  npm run build:static
)

mkdir -p server/webui/dist
rsync -a web/out/ server/webui/dist/

CGO_ENABLED=0 go build -tags embedui -o artex ./cmd/artex
```

Use a fresh checkout and generated-output directory. If stale generated files already exist, start from a new checkout rather than deleting potentially useful files.

Copy the **contents** of `web/out/`, including `_next`, into `server/webui/dist/`; avoid an accidental `dist/out` nesting. Omitting `-tags embedui` produces a backend without the embedded UI.

This direct build leaves the default development version identifier. It does not claim to be an official release.

Sources: [build.sh](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/build.sh), [frontend scripts](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/web/package.json), [embedded frontend handler](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/webui_embed.go)

## 6. First local idle startup

Prerequisites: the database is the new empty database created above; the checkout has no old `data`, `jwt.key`, or staged update artifacts. Do not import old tasks, model profiles, credentials, or remote-service configurations.

```bash
unset ANTHROPIC_API_KEY OPENAI_API_KEY
unset ARTEX_PG_DSN ARTEX_SKILL_DIR
unset ARTEX_LLM_PROVIDER ARTEX_LLM_MODEL ARTEX_LLM_BASE_URL ARTEX_LLM_PROXY
export ARTEX_CONFIG="$PWD/config.json"

./start.sh -addr 127.0.0.1:8787 -proxy 127.0.0.1:8788 -data "$PWD/data"
```

Both application HTTP and the traffic-recording proxy are explicitly bound to loopback. Do not configure a browser/system proxy, import its CA, forward these ports, or expose them to a LAN or the Internet.

The reviewed source indicates:

- Without a model configuration, the engine remains idle
- A new database seeds the browser MCP and ScopeSentry as **disabled**
- Enabled MCPs with empty tool caches are discovered automatically at startup; that can launch a subprocess or contact a configured remote service
- Persisted model configuration takes precedence over environment variables
- Existing nonterminal task runtimes can be restored on startup

**Unsetting environment variables does not make an old database a safe blank instance.** Use a genuinely new database and data directory.

Loopback binding limits incoming connections; it does not prove the application has no outbound capability. This guide does not claim to provide complete network isolation and does not ask you to change host firewall or security settings. It preserves the application's existing approval/safety controls.

Sources: [main/startup flags](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/cmd/artex/main.go), [model configuration and task restoration](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/server.go#L237-L294), [disabled browser MCP seed](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/db/db.go#L255-L269), [MCP discovery](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/mcpdiscover.go), [environment model configuration](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/agent/provider.go#L145-L192)

## 7. Health checks without creating tasks

In another terminal, access only the local instance:

```bash
curl --fail --silent --show-error http://127.0.0.1:8787/api/health
curl --fail --silent --show-error http://127.0.0.1:8787/api/auth/status
```

Expected observations, **not verified results**:

- Health returns JSON with `ok: true`, `service: "artex"`, and `version`
- Before initial password setup in a new database, auth status returns `initialized: false`
- Health is an HTTP liveness response, not a comprehensive dependency-readiness test; auth status performs a database read
- Open `http://127.0.0.1:8787/setup` in your browser and personally set a new administrator password
- The login username is `ARTEX`; source password validation requires at least 8 characters and at most 72 bytes
- Inspect the blank UI only; do not create tasks, targets, assets, model configurations, or enable MCPs

Before marking startup successful, record actual tool versions, the configuration path and idle message in startup logs, actual listening addresses, whether the UI loaded, and the check timestamp. Do not paste passwords, tokens, private infrastructure details, or raw sensitive logs.

Sources: [health handler](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/server.go#L947-L949), [authentication/setup](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/auth.go)

## 8. Frontend-only mock preview

For UI study without a Go backend, database, or model credentials, the repository supports mock mode:

```bash
cd web
npm ci
NEXT_PUBLIC_MOCK=1 npm run dev -- --hostname 127.0.0.1 --port 5173
```

Open `http://127.0.0.1:5173`. This is simulated UI data, not evidence of successful backend deployment. Mock mode removes the development API reverse proxy; it is not a guarantee that every browser network request is isolated.

The port is explicit because `dev.sh` describes 5173 but invokes `npm run dev` without setting a port, and the package script is simply `next dev`.

Stop with Ctrl-C. Before building the real UI afterward, unset mock-related environment variables and rebuild.

Sources: [mock flag](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/web/src/lib/mock/enabled.ts), [Next configuration](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/web/next.config.mjs), [dev.sh](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/dev.sh), [package scripts](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/web/package.json)

## 9. Troubleshooting

- **Go version rejected:** follow `go.mod`'s 1.26.3 requirement, not only an older script's broader version message
- **Dependency unavailable:** retain the package name, exact version, and redacted error; do not disable checksums or use unknown substitutes
- **Database connection failure:** check actual port, role, database, the logged configuration path, and whether `ARTEX_PG_DSN` overrides the file
- **Database creation/migration permission failure:** have the database administrator precreate the dedicated database and verify the application's object permissions; do not switch to a superuser
- **API works but UI/assets are missing:** verify `web/out/index.html`, `server/webui/dist/index.html`, and the `embedui` build tag
- **Port already in use:** choose an unused loopback port and update the check URLs; do not kill an unidentified process
- **start.sh cannot find ./artex:** this guide builds the binary in the checkout root; `build.sh` defaults to a different output location under `dist`
- **Old tasks, an existing admin password, enabled MCPs, or model profiles appear:** stop the check and verify database/data selection; do not interact with those tasks
- **Restart loop:** `start.sh` retries abnormal exits with backoff; stop with Ctrl-C and inspect the first failure
- **Readiness differs from health:** a 200 response from `/api/health` does not validate the database, frontend, model configuration, or the whole application

## 10. Shutdown, retention, and cleanup

For a foreground run, press Ctrl-C. The supervisor forwards a termination signal to the child; the backend attempts graceful shutdown. Verify the process has exited, the application/proxy listeners have stopped, and the local health endpoint no longer responds.

Do not stop a shared PostgreSQL service or automatically delete the database, role, data directory, or backups.

To retain an instance, preserve:

- A PostgreSQL database backup
- `config.json`
- `data/`
- The actual `skills/` directory
- **`jwt.key` beside the executable**

At this revision, JWT key storage is beside the executable, not solely inside `data/`. Backing up only `data/` is insufficient. In a container, mounting only `/app/data` likewise does not cover the current JWT key location.

Sources: [supervisor](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/start.sh), [shutdown](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/cmd/artex/main.go), [JWT key location/migration](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/server/auth.go#L46-L92)

## 11. Why the existing Docker path is not the verified route here

The README states that the original Docker deployment source is no longer available, but Compose still references `autumn27/artex:latest`. The Dockerfile is not a self-contained source-build image: it expects a prebuilt Linux binary at `dist/${TARGETARCH}/artex`.

Other unresolved points:

- The Dockerfile executes a remote installation script and downloads `latest` tool packages/browser artifacts; it is not fully pinned
- It does not declare a non-root `USER`
- Compose's HTTP port mapping for 8787 is not restricted to loopback
- Building/running Docker requires appropriate Docker access, potentially involving a privileged daemon
- Image availability/provenance, digests, dependency downloads, and architecture matching have not been tested
- The current JWT key location and documented volume persistence need reconciliation

Do not treat the original Compose command, automatic installer, or an unknown replacement image as a validated local deployment procedure.

Sources: [README](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/README.md), [Dockerfile](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/Dockerfile), [Compose](https://github.com/Laisky/ARTEX/blob/5c0dbd4bec940f3c0faf20705a56d879b57d3dfe/docker-compose.yml)

## Acceptance checklist

- [ ] Record pinned source revision, OS, and actual toolchain versions
- [ ] Build successfully using trusted dependency sources
- [ ] Start using a genuinely new local database and independent data directory
- [ ] Verify HTTP/proxy listeners are loopback-only
- [ ] Confirm no model credentials, targets, or enabled MCPs
- [ ] Verify health, auth status, and UI without creating tasks
- [ ] Verify Ctrl-C stops the application and proxy
- [ ] Attach only redacted observations and identify tested platforms
- [ ] Keep all unverified steps explicitly labeled until tested
