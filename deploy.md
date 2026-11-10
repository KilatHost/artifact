# Deploy Kilat Artifact

This guide covers the current single-host Docker Compose deployment, plus requirements for a managed cloud installation. It does not provision infrastructure or describe a live Kilat Cloud service.

> **Release status:** Compose configuration has been validated. The Linux image, container Chromium sandbox, S3 integration and backup recovery have not been exercised. Complete the acceptance checklist before using real customer data.

## 1. Prepare and start

### Requirements

- Linux host with Docker Engine, Docker Compose v2 and Git.
- Persistent disk for PostgreSQL, uploaded files, Docker images and backups.
- A hostname and HTTPS reverse proxy for remote users or hosted AI connectors.
- A host/kernel configuration that lets non-root Chromium use its sandbox.

No host Ruby, Node or PostgreSQL installation is needed. Ruby **3.3.13** and Chromium are installed in the image. Build on Linux or a remote builder, not the project's macOS development workstation.

There is no measured minimum host size yet. PDF requests launch Chromium synchronously in the web process; size for concurrent renders, not just idle Rails memory. Do not advertise capacity until load is measured.

### Install

```sh
git clone https://github.com/KilatHost/artifact.git
cd artifact
cp .env.example .env
chmod 600 .env
openssl rand -hex 64
openssl rand -hex 64
```

Edit `.env`, using separate generated values:

| Variable | Required value |
| --- | --- |
| `SECRET_KEY_BASE` | Strong persistent secret for Rails signing/session protection |
| `POSTGRES_PASSWORD` | Independent hex password; Compose inserts it into a database URL |
| `APP_HOST` | Hostname only, without scheme, path or port; `localhost` for local access |
| `PORT` | Host loopback port; default `3000` |
| `FORCE_SSL` | `false` for local HTTP; `true` behind correctly configured HTTPS proxy |

Never commit `.env`, credential keys, database dumps or uploaded files. Preserve `SECRET_KEY_BASE` across upgrades. Changing `POSTGRES_PASSWORD` in `.env` does not change an existing PostgreSQL role's password; rotate both deliberately during maintenance.

```sh
docker compose config --quiet
docker compose build web
docker compose up -d
curl --fail http://localhost:3000/up
docker compose ps
```

Compose starts a private PostgreSQL 17 service, waits for its health check and starts Rails. The web entrypoint runs `db:prepare`, creating or migrating the configured database. Uploaded files and PostgreSQL data use separate named volumes.

Open <http://localhost:3000>, then create the first account. There is no seeded administrator or default password. Each account owns one workspace. After the first account, sign-up is closed unless you set `ALLOW_SIGNUP=true`.

For a remote host without a public proxy yet, use an SSH tunnel:

```sh
ssh -L 3000:127.0.0.1:3000 your-user@your-server
```

### HTTPS and proxy

The app binds to `127.0.0.1:${PORT}` on the Docker host. A reverse proxy running directly on that host can reach it. A proxy in another container cannot use its own loopback address; deliberately attach it to the app network instead, without publishing the database.

Set:

```dotenv
APP_HOST=artifacts.example.com
FORCE_SSL=true
```

Configure the proxy to:

- Terminate valid public TLS and redirect HTTP to HTTPS.
- Preserve `Host` and set trusted `X-Forwarded-Proto: https`.
- Route `/mcp`, `/oauth/*`, `/.well-known/*`, `/p/*` and normal app paths without rewriting them.
- Never cache authenticated pages, OAuth responses, MCP responses or public artifact pages. A public link follows the latest version, and unpublish depends on endpoints being rechecked.
- Thruster in the image refuses request bodies over 22 MiB (`MAX_REQUEST_BODY`). Set the same or a lower limit at the proxy so oversized uploads stop there.
- Set bounded request timeouts that permit expected PDF renders; apply rate and connection limits.

Restart after configuration changes:

```sh
docker compose up -d --force-recreate web
curl --fail https://artifacts.example.com/up
```

`/up` proves Rails responds; it does not independently prove database, storage, OAuth or PDF health. The configured hostname is enforced in production. If requests return a blocked-host error, check `APP_HOST` and forwarded `Host`; do not disable host validation as a shortcut.

Do not expose PostgreSQL, the Rails upstream port or Chromium debugging ports publicly. Keep signup and OAuth endpoints reachable only by intended users when operating a private instance. Proxy-wide browser authentication may break hosted MCP clients; use compatible network access controls and test the complete authorization flow.

## 2. Storage, recovery and upgrades

### Default storage

Compose persists:

| Volume | Content |
| --- | --- |
| `postgres_data` | Accounts, workspaces, versions, design kits, OAuth records and token digests |
| `artifact_storage` | Original uploaded files |

Volume names are prefixed by the Compose project name. Keep that name stable across deployments, or explicitly migrate volumes. Moving the checkout or changing `COMPOSE_PROJECT_NAME` can select empty volumes instead of existing data.

`docker compose down` preserves named volumes. **`docker compose down -v` permanently removes these volumes. Do not use it for upgrades or ordinary shutdown.**

### S3-compatible storage

The app supports `STORAGE_SERVICE=s3` and these runtime variables:

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Region; default `us-east-1` |
| `S3_BUCKET` | Private bucket name |
| `S3_ENDPOINT` | Optional alternate S3-compatible endpoint |
| `S3_PATH_STYLE` | Set `true` only if the provider requires path-style addressing |

Use the AWS SDK credential chain, preferably a narrowly scoped workload role. For other providers, inject credentials through a secret manager or protected runtime configuration. Do not put them in the image.

The supplied Compose file does **not** pass these variables to Rails. Add them with a reviewed Compose override or deployment configuration; setting an unreferenced value in `.env` alone does not pass it into a container.

Keep the bucket private, encrypt it, enable suitable retention/versioning and grant only required access. Application authorization remains responsible for private downloads. Existing local files are not automatically migrated when selecting S3. Plan and verify that migration before changing backends.

### Back up

Back up database and blobs as one consistent checkpoint. For the current single-host deployment, stop web writes while taking both. Commands below write sensitive backup files on the host; protect and encrypt them before copying off-host.

```sh
mkdir -p backups
chmod 700 backups
backup_id=$(date -u +%Y%m%dT%H%M%SZ)
umask 077
docker compose stop web
docker compose exec -T db pg_dump -U kilat -d kilat_artifact_production -Fc > "backups/${backup_id}.dump"
docker compose run --rm --no-deps --entrypoint tar web -C /rails/storage -czf - . > "backups/${backup_id}-storage.tar.gz"
docker compose start web
```

Run each command only after the preceding one succeeds. If a backup command fails, do not label that checkpoint complete; restart the web service after resolving the failure. Preserve the matching application revision, deployment configuration and secrets separately. Encrypt backups, store an off-host copy and verify retention against available disk.

S3 deployments need a matching object checkpoint or a tested version-recovery strategy instead of the local storage archive. A database dump alone is not an artifact backup.

### Restore

Restore first into an isolated environment, never over the only copy of customer data.

1. Select matching database/blob backups and the recorded application revision.
2. Prepare a separate deployment with fresh empty volumes and a separate hostname. Keep public access disabled.
3. Start PostgreSQL only: `docker compose up -d db`.
4. Restore the dump into its empty database with `pg_restore --exit-on-error --no-owner --no-privileges`, using the deployment's database user. Restore the storage archive into `/rails/storage` as the Rails UID/GID `1000:1000`.
5. Start the application. Inspect migrations before allowing the entrypoint to change a restored older database.
6. Verify owner login, original file bytes, version history, a private download and PDF export. Confirm unrelated users cannot access private artifacts.
7. Record the restore result and recovery time. Only then consider replacing a damaged deployment.

No restore drill has passed yet. Do not claim a recovery objective until this procedure has been exercised with real backups.

### Upgrade and rollback

- Record the running source revision and retain its built image.
- Take a verified pre-upgrade checkpoint. Review migrations for compatibility and data changes.
- Fetch the approved release, build its image and replace the web service with `docker compose up -d --no-deps web`.
- Verify health plus a real create/edit/export/MCP flow before ending maintenance.

A code rollback is safe only when the previous application supports the current schema. Otherwise restore the matching pre-upgrade database and blobs during maintenance. That loses writes made after the checkpoint; obtain explicit approval before taking that path. Do not blindly run migrations down or restore over current data.

## 3. Acceptance, monitoring and cloud limits

### Acceptance checklist

Before using real customer data:

- [ ] Linux image builds with Ruby 3.3.13; migrations and normal startup succeed.
- [ ] HTTPS works without redirect loops; cookies and host checks behave correctly.
- [ ] Two accounts cannot read or modify each other's artifacts, versions, files, kits or connections.
- [ ] Markdown/HTML/rich-text/file create and edit work; stale browser edits are rejected.
- [ ] A public link shows each new version at once; unpublish removes access for everyone but the owner.
- [ ] An HTML artifact's scripts run, while `document.cookie` and `fetch('/artifacts')` inside it fail.
- [ ] Original file downloads match uploaded bytes after a container restart.
- [ ] PDF renders inside the container with no artifact-controlled network access.
- [ ] HTML/ZIP/source downloads contain the selected saved version.
- [ ] OAuth registration, browser consent, PKCE, refresh and revocation work through the actual proxy.
- [ ] Read/write/publish permissions remain distinct in a real MCP client.
- [ ] At least two real AI clients read and revise the same artifact ID without a lost update.
- [ ] Backup restoration passes in an isolated deployment.

### Operations

```sh
docker compose ps
docker compose logs --tail=100 web
docker compose logs --tail=100 db
docker compose logs --tail=100 jobs
```

The `jobs` service purges artifacts deleted more than 7 days ago. If it stops, deleted artifacts stay in Deleted and keep using storage until it runs again.

Logs can still contain operational metadata. Do not share raw logs before checking for secrets or private user content. Configure host/container log rotation; default unbounded Docker logs can exhaust disk.

Monitor app errors and latency, database connections/storage, upload volume, backup age and restore results, Chromium crashes/render duration, memory pressure and outbound traffic. Alert on disk exhaustion before PostgreSQL or uploads fail.

PDF export runs synchronously, one render per web process; a second request gets a 503 asking to try again. It is not queued, quota-controlled or cached. Set external request limits before broad public access. Chromium runs with `--no-sandbox` because Docker's default seccomp profile stops its sandbox; scripts are disabled and all requests aborted during the render, and the container runs as a non-root user.

### Managed cloud readiness

The same app can use managed PostgreSQL and private S3-compatible storage, but this is not a finished hosted platform. Before a cloud launch, provide:

- TLS, secret delivery, managed database recovery, object retention, monitoring and a tested incident/recovery procedure.
- A configured shared rate-limit cache before running multiple Rails processes/replicas. The repository does not configure that cache.
- Measured PDF concurrency limits and customer storage/transfer limits. No built-in billing, storage quota enforcement or metered cloud plans exist yet.

Keep database and object storage private. Test tenant isolation after changes to proxying, storage or authentication. Do not label named AI clients compatible until each has passed its real connection flow.

### Cost model

No mandatory model API cost is incurred by this service. Hosting cost is:

```text
compute + PostgreSQL + stored artifact versions + original files
+ backups + download transfer + object requests + monitoring
```

PDF rendering adds CPU/memory demand; immutable versions increase retained storage. Measure render seconds, peak concurrency, retained bytes and downloads before choosing an instance or price. No hosting quote, capacity promise or production cost benchmark is available yet.
