# Configuration

[Documentation index](README.md) · [Deployment](../deploy.md) · [Troubleshooting](troubleshooting.md)

## How settings reach the app

Copy [`.env.example`](../.env.example) to `.env` for Compose interpolation. A value in `.env` is **not** automatically a container environment variable: only entries in [compose.yaml](../compose.yaml) are forwarded. For settings not forwarded there, use a reviewed Compose override or another runtime environment configuration. Never commit secrets; protect `.env` with `chmod 600 .env`.

Defaults below distinguish Compose from running Rails directly. Boolean checks are case-sensitive. Preserve signing secrets and both persistent volumes across upgrades.

## Deployment and application

| Variable | Default | Purpose / delivery |
| --- | --- | --- |
| `SECRET_KEY_BASE` | Required by Compose; no example value | Rails signing/session secret. Generate with `openssl rand -hex 64`; web and jobs receive it. |
| `POSTGRES_PASSWORD` | Required by Compose | Independent database password. Use hex: Compose interpolates it unescaped into `DATABASE_URL`. Changing `.env` does not rotate an existing database role. |
| `ARTIFACT_VERSION` | `1.0.0` | Compose image tag; change with the checkout during upgrades. |
| `ARTIFACT_IMAGE` | `ghcr.io/kilathost/artifact` | Compose image repository for web/jobs; not an app setting. Both services also declare `build: .`. |
| `APP_HOST` | `localhost` | Allowed production hostname, without scheme, port or path; forwarded to web/jobs. `/up` is excluded from host checking. |
| `PORT` | `3000` | Compose host loopback port mapped to container port 80. Direct Puma also reads it as its listening port. |
| `FORCE_SSL` | Compose/example `false`; direct production `true` | Exact `true` enables production `assume_ssl` and `force_ssl`. Use behind a correctly configured TLS proxy. |
| `ALLOW_SIGNUP` | Compose/example `false`; otherwise unset | Exact `true` permits anyone to register after the first account; the first account is always allowed. |
| `ARTIFACT_EXTERNAL_RESOURCES` | `true` | Exact `false` blocks external artifact libraries, fonts and HTTPS images; inline/data resources remain. Forwarded to web. |
| `KILAT_PUBLIC_LINKS` | `latest` | `pinned` pins newly published artifacts until explicitly updated; existing unpinned publications keep following latest. Forwarded to web. |
| `BROWSER_PATH` | Compose `/usr/bin/chromium`; otherwise browser discovery | Chromium executable for PDF export; forwarded to web. |
| `RAILS_ENV` | Compose `production` | Rails environment; use `test` for disposable test databases. Web/jobs receive it. |
| `RAILS_LOG_TO_STDOUT` | Compose `true` | Set on web/jobs. Production config already explicitly logs to STDOUT; it does not branch on this variable. |
| `RAILS_LOG_LEVEL` | `info` in production | Production logging verbosity; not forwarded by supplied Compose. |
| `DATABASE_URL` | Compose `postgres://kilat:<POSTGRES_PASSWORD>@db:5432/kilat_artifact_production`; otherwise unset | Database connection URL. Overrides database.yml database selection; forwarded to web/jobs. Direct development/test database names are `kilat_artifact_development` / `kilat_artifact_test`. |
| `POSTGRES_USER` | Compose `kilat` | PostgreSQL image initialization user, db service only. |
| `POSTGRES_DB` | Compose `kilat_artifact_production` | PostgreSQL image initialization database, db service only. |

## Storage

These variables are read by [production config](../config/environments/production.rb) and [storage config](../config/storage.yml), but are **not forwarded** by the supplied Compose file. S3 support is not yet verified; selecting it does not migrate existing local files. Use the AWS SDK credential chain (prefer a scoped workload role), not credentials baked into an image.

| Variable | Default | Purpose |
| --- | --- | --- |
| `STORAGE_SERVICE` | `local` in production | Active Storage service: local disk at `storage/`, or `s3`. Development uses local; test uses `tmp/storage`. |
| `AWS_REGION` | `us-east-1` | S3 region. |
| `S3_BUCKET` | `kilat-artifact` | Private bucket name. |
| `S3_ENDPOINT` | Unset | Alternate S3-compatible endpoint. |
| `S3_PATH_STYLE` | `false` | Exact `true` enables path-style addressing. |

## Runtime and development

These settings appear in [config/](../config). They are not forwarded by the supplied Compose file unless listed above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `RAILS_MAX_THREADS` | Puma `3`; database pool `5` when unset | Sets both Puma thread bounds and the database connection pool when supplied. |
| `WEB_CONCURRENCY` | See Puma defaults | Puma's supported worker control, mentioned in config/puma.rb; set only when deliberately sizing multiple workers. |
| `PIDFILE` | Unset | Optional Puma PID file; development otherwise uses its standard PID path. |
| `BUNDLE_GEMFILE` | Repository `Gemfile` | Boot selects this file only when the variable is not already set. |
| `CI` | Unset | A present value enables eager loading in test configuration. |

For local development, inherited `PGUSER`, `PGPASSWORD` and `PGHOST` can redirect PostgreSQL connections; unset them and any unintended `DATABASE_URL` before running Rails. See [Development](development.md) for explicit database commands and `PARALLEL_WORKERS=1` test execution.
