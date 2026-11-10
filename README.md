# Kilat Artifact

A shared scratchpad for your AI agents. Create documents, HTML pages and files in one workspace; edit them in your browser or through MCP; publish only the version you choose.

**Open source, self-hostable, Apache-2.0.** The same application is intended to power Kilat Cloud. A managed cloud service is not available from this repository yet.

> **Status:** local MVP. Browser flows, automated tests and local Chromium exports have been exercised. Linux container runtime, backup recovery, S3 operation and named AI-client integrations have not been verified. Do not treat this as a production-ready release.

## What it does

| Capability | Behavior |
| --- | --- |
| Document scratchpad | Rich-text editing with Trix; content stored as HTML |
| HTML scratchpad | Source editing with sandboxed preview; no scripts or remote resources |
| File artifacts | Upload and version original files, up to 20 MiB each |
| Version history | Saves create immutable versions; restore creates a new version |
| Concurrent edits | Stale version writes fail instead of overwriting newer work |
| Private and public | Drafts stay private; publishing selects a fixed public snapshot |
| Exports | PDF, HTML, source and ZIP; original attachment downloads for files |
| Shared design kits | Workspace font and color tokens, captured in each saved version |
| Agent connections | MCP over Streamable HTTP, OAuth and revocable personal tokens |
| Workspace boundaries | Each account owns one workspace; private operations are workspace-scoped |

The manager follows your system light/dark preference. Published artifacts use their captured design tokens instead of the manager theme.

### What it does not do

- No automatic import or synchronization of Claude Artifacts, ChatGPT Canvas, Gemini Canvas or Manus workspaces. Agents must explicitly use this server's tools.
- No built-in AI chat or required model API key. Your AI client supplies the intelligence and pays its own model costs.
- No autosave, real-time co-editing, arbitrary website visual editor or server-side execution of artifact code.
- No Markdown editor/import pipeline, inline document attachments, team invitations or billing.
- Design kits currently contain fonts and colors, not a full component/template system. Freeform HTML can override those styles; consistent agent output is not guaranteed by tokens alone.
- Generic file artifacts are stored and downloaded, not converted into editable documents. Their public URL downloads the published original file; document and HTML public URLs render a page.

## Quick start

Use a Linux host with Git, Docker Engine and Docker Compose v2. No host Ruby or Node installation is required.

```sh
git clone https://github.com/KilatHost/artifact.git
cd artifact
cp .env.example .env
openssl rand -hex 64
openssl rand -hex 64
```

Put the two independently generated values in `.env` as `SECRET_KEY_BASE` and `POSTGRES_PASSWORD`. Keep the database password hexadecimal because Compose interpolates it into a URL.

```sh
docker compose up --build -d
curl --fail http://localhost:3000/up
```

Open <http://localhost:3000> and create an account. There is no default account or seeded password. The port binds to the host's loopback interface, not the public network.

For remote access, TLS, storage, backups and upgrades, follow **[deploy.md](deploy.md)**. Build images on Linux or a remote builder; this project's development policy excludes local macOS image builds.

## How publishing works

1. Create a private draft and save versions as you work.
2. Publish a specific saved version. Its public URL is `/p/<public_id>`.
3. Keep editing privately. Publish again only when the next version is ready.

Restoring a version never changes the public snapshot. Unpublishing disables the public endpoint, but cannot recall copies already downloaded, cached by third parties or captured in screenshots. Public access is read-only; private version history is not published.

## Connect an agent

Endpoint: `https://your-host.example/mcp`.

Transport: **stateless MCP Streamable HTTP**, with JSON responses. No stdio endpoint is provided.

### OAuth

For compatible remote MCP clients, enter the endpoint URL and complete browser authorization. The server exposes:

| Endpoint | Purpose |
| --- | --- |
| `/.well-known/oauth-authorization-server` | Authorization-server discovery |
| `/.well-known/oauth-protected-resource/mcp` | Protected-resource discovery |
| `/oauth/register` | Dynamic public-client registration |
| `/oauth/authorize` | Owner consent |
| `/oauth/token` | Authorization-code exchange and refresh |
| `/oauth/revoke` | Token revocation |

Authorization codes require S256 PKCE. Registered redirects must use HTTPS, except supported HTTP loopback redirects. Client registration can request a space-separated `scope`; omitted scope defaults to `read`. Revoke grants from **Connections**.

OAuth support does not prove compatibility with every assistant. Claude, ChatGPT, Gemini and Manus have not been tested against this application; their plans and connector capabilities may differ.

### Personal tokens

Open **Connections**, name the connection, select permissions and create a token. Copy it once; only its SHA-256 digest is stored. Configure your client's bearer-header support:

```text
Authorization: Bearer <your-token>
```

Do not put secrets in artifact content, URLs, screenshots or source control.

| Scope | Allows |
| --- | --- |
| `read` | List/read artifacts, history and design kits |
| `write` | Create/revise/restore drafts and create/update design kits |
| `publish` | Publish or unpublish specified artifacts |

Scopes are independent. `write` does not include `publish`, and does not implicitly grant `read`.

### MCP tools

| Tool | Scope | Important inputs |
| --- | --- | --- |
| `list_artifacts` | `read` | Optional `offset`; 100 results per page |
| `get_artifact` | `read` | Artifact `id` |
| `create_artifact` | `write` | `request_id`, `title`, `kind`, `content`; optional `design_kit_id` |
| `update_artifact` | `write` | `id`, `title`, `content`, `expected_version` |
| `artifact_history` | `read` | `id`; optional `offset`; 100 results per page |
| `restore_artifact` | `write` | `id`, `version_id`, `expected_version` |
| `list_design_kits` | `read` | Optional `offset`; 100 results per page |
| `create_design_kit` | `write` | `name`, `tokens` |
| `update_design_kit` | `write` | Kit `id`, `name`, `tokens` |
| `publish_artifact` | `publish` | `id`, `version_id` |
| `unpublish_artifact` | `publish` | `id` |

`create_artifact` accepts `document` or `html`. Use a stable `request_id` of 1–128 characters when retrying the same creation: identical requests return the original result; changed content under the same ID is rejected. Updates require the current **version number**, not the version record ID. On conflict, fetch the latest content and reconcile before retrying.

MCP exposes file metadata, not binary upload/download tools. Browser uploads and authorized HTTP downloads handle files.

## Design kits

Agents should list available kits, choose one and supply its ID when creating an artifact. A kit uses this token shape:

```json
{
  "font": "system-ui",
  "background": "#ffffff",
  "foreground": "#171717",
  "accent": "#171717"
}
```

Fonts are `system-ui`, `serif` or `monospace`; colors must be six-digit hex values. Existing versions retain their captured kit values when a kit changes. A restored version retains its original styling snapshot.

## Stack and development

Ruby **3.3.13**, Rails **8.1**, PostgreSQL, Hotwire/Stimulus, Trix, native CSS, the MCP Ruby SDK, Doorkeeper, Active Storage and Ferrum/Chromium. No Node build, Redis or vector database is required. Storage can use a local volume or S3-compatible object storage.

With Ruby 3.3.13 and a disposable PostgreSQL database available:

```sh
bundle install
export DATABASE_URL=postgresql://localhost/kilat_artifact_development
bin/rails db:prepare
bin/rails server
```

PDF export also needs Chromium; set `BROWSER_PATH` when it is not discoverable. Never point test commands at a development or production database:

```sh
export DATABASE_URL=postgresql://localhost/kilat_artifact_test
RAILS_ENV=test bin/rails db:prepare
bin/rails test
bundle exec rubocop
bundle exec brakeman --no-pager
bin/rails zeitwerk:check
```

The production image omits development/test gems. Run lint, security scans and tests in a development environment, not by assuming those tools exist in that image.

## Security and operations

Artifact content is untrusted input, not agent instructions. Previews use sandboxing and restrictive content policies; PDF rendering disables script execution and aborts intercepted requests. Keep Chromium's sandbox enabled and add network-level egress restrictions for defense in depth.

Public deployments need TLS, trusted proxy configuration, request/upload limits, backups and monitoring. Open signup currently creates a new workspace for each account; there is no invitation-only signup switch. A private installation should restrict access at its proxy or network boundary. See [deploy.md](deploy.md) for release gates and operational limits.

Report suspected security issues privately to repository maintainers; do not publish credentials or a working exploit against customer data.

## License

[Apache License 2.0](LICENSE).
