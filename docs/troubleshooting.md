# Troubleshooting

[Documentation index](README.md) · [Configuration](configuration.md) · [Deployment](../deploy.md)

## Installation and startup

| Symptom | Check / action |
| --- | --- |
| `docker compose pull` returns 401 / unauthorized | The configured GHCR package may require access or be private. Verify the image/tag and package permissions; authenticate with an authorized account if appropriate. The repository's release workflow publishes to GHCR, but does not guarantee your access. Alternatively build the checked-out release locally with `docker compose build` then `docker compose up -d --wait --pull never`. Never paste registry credentials into an issue. |
| Compose still pulls an image despite `build: .` | Services declare both `image` and `build`; `build: .` alone does not mean a normal `up` builds your checkout. Run `docker compose build` or `docker compose up -d --build --wait`. Building tags the result with the configured image name; pull again to return to the release image. |
| Required variable error | Supply independent `SECRET_KEY_BASE` and hex `POSTGRES_PASSWORD` in `.env`. Validate interpolation with `docker compose config --quiet` without printing secrets. |
| Blocked host in production | Match `APP_HOST` to the actual hostname and preserve the proxy's `Host` header. Do not disable host validation. `/up` is excluded, so a healthy probe does not disprove a host mismatch. |
| Local Rails cannot connect to PostgreSQL | Start PostgreSQL; unset inherited `PGUSER PGPASSWORD PGHOST DATABASE_URL`, then select the intended local database. See [local setup](development.md#local-setup). |
| Changing `.env` did not change behavior | Recreate affected containers; for web use `docker compose up -d --force-recreate web`. Variables absent from Compose's environment mapping need an override, not just a new `.env` entry. |

## Accounts and agents

- **Sign-up closed:** after the first account, registration redirects to sign-in unless `ALLOW_SIGNUP=true`. Only enable open registration deliberately; each account creates its own workspace. Create the first account before public exposure.
- **Forgotten password:** there is no email reset flow. An operator runs `docker compose exec web bin/rails users:reset_password EMAIL=person@example.com`. It prints a random password once and revokes the account's OAuth connections.
- **MCP HTTP 401 `invalid_token`:** check the bearer header, token expiry/revocation, and configured endpoint. OAuth clients should reauthorize as needed; personal-token plaintext is displayed only once. Do not share it for debugging.
- **MCP `permission_denied`:** scopes are independent. `write` includes neither `read` nor `publish`. Review granted permissions in **Connections**; see [MCP scopes](mcp.md#personal-tokens).
- **MCP `version_conflict`:** read latest content, merge your intended change, retry with the new `expected_version`. If inputs change, use a new request ID. Reusing an ID with different inputs yields `idempotency_mismatch`.

## Rendering, sharing and storage

- **PDF HTTP 503:** “Another PDF is being made. Try again in a few seconds.” A per-process mutex permits only one Chromium PDF render at a time. Retry later; do not treat this as a missing artifact. If Chromium cannot start, check installation and `BROWSER_PATH`.
- **PDF differs from interactive HTML:** export disables JavaScript and aborts all network requests. Script-driven charts/decks and external resources do not render as they do in a browser; use a static print layout.
- **External assets missing:** artifact CSP allows only the documented hosts and blocks fetch/XHR; `ARTIFACT_EXTERNAL_RESOURCES=false` also blocks external libraries, fonts and HTTPS images. Inline static content is more portable. See [security](../README.md#security-and-operations).
- **Public link did not advance:** with `KILAT_PUBLIC_LINKS=pinned`, use **Update public link** or explicitly publish again with delegated publish scope. Unpublishing stops anonymous access, not copies already saved elsewhere.
- **Upload refused:** original files are limited to 20 MiB; the image's Thruster body limit is 22 MiB. Check proxy request limits too. Generic uploads remain files, not editable conversions.
- **Data after restart:** preserve both `postgres_data` and `artifact_storage`. `docker compose down` keeps them; `docker compose down -v` deletes them permanently. Restore matched database/blob checkpoints using the [restore drill](../deploy.md#restore).
- **Deleted artifact:** restore from the web app within seven days. The scheduled purge removes older archived artifacts with versions and files; unarchiving does not republish them.

These behaviors are defined by [Compose](../compose.yaml), [registration](../app/controllers/registrations_controller.rb), [MCP](../app/services/artifact_mcp.rb), [PDF export](../app/services/artifact_exports.rb), [artifacts](../app/models/artifact.rb) and the [deployment guide](../deploy.md). `/up` only proves Rails responds; verify login, storage, OAuth and PDF separately before relying on an installation.
