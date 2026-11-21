<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/kilat-artifact-dark.svg">
    <img src="docs/brand/kilat-artifact-light.svg" width="88" height="88" alt="Kilat Artifact">
  </picture>
</p>

<h1 align="center">Kilat Artifact</h1>

<p align="center">A shared scratchpad for you and your AI agents.<br>Markdown, HTML pages and files, versioned, with one link that always shows the latest version.</p>

<p align="center">
  <a href="https://github.com/KilatHost/artifact/actions/workflows/ci.yml"><img src="https://github.com/KilatHost/artifact/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-0a0a0a" alt="License: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/Ruby-3.3-0a0a0a?logo=ruby&logoColor=white" alt="Ruby 3.3">
  <img src="https://img.shields.io/badge/Rails-8.1-0a0a0a?logo=rubyonrails&logoColor=white" alt="Rails 8.1">
  <img src="https://img.shields.io/badge/PostgreSQL-17-0a0a0a?logo=postgresql&logoColor=white" alt="PostgreSQL 17">
  <a href="deploy.md"><img src="https://img.shields.io/badge/self--host-docker%20compose-0a0a0a?logo=docker&logoColor=white" alt="Self-host with Docker Compose"></a>
  <a href="#connect-an-agent"><img src="https://img.shields.io/badge/MCP-OAuth%20%2B%20tokens-0a0a0a" alt="MCP with OAuth and tokens"></a>
</p>

<p align="center"><a href="#quick-start">Quick start</a> · <a href="#connect-an-agent">Connect an agent</a> · <a href="deploy.md">Deploy</a> · <a href="#security-and-operations">Security</a></p>

**Open source, self-hostable, Apache-2.0.** Create and edit in your browser or through MCP from Claude and other agents. The same application is intended to power Kilat Cloud; a managed service is not available from this repository yet.

> **Status:** early release. CI runs the test suite and a Docker Compose check on Linux (sign-up, publish, PDF, file round trip, restart, backup and restore). Claude has been tested over OAuth; ChatGPT, Gemini and Manus have not. S3 storage is not yet verified.

## What it does

| Capability | Behavior |
| --- | --- |
| Markdown | GitHub-flavoured Markdown, stored as written and rendered on view; raw HTML is dropped |
| HTML | Full pages or fragments, shown as written. Scripts run in a sandbox with no access to the app; libraries load from cdnjs, jsdelivr, unpkg and the Tailwind CDN |
| Rich text | Browser editing with Trix; content stored as sanitized HTML |
| Doc, Sheet, Slides | Structured JSON sources rendered locally in Ruby; edit JSON in the source textarea or create through MCP |
| File artifacts | Upload and version original files, up to 20 MiB each |
| Version history | Saves create immutable versions; restore creates a new version |
| Concurrent edits | Stale version writes fail instead of overwriting newer work |
| Private and public | Private until you make it public; a public link always shows the latest version |
| Delete and restore | Deleting ends public access at once; restore within 7 days, then it is purged with its versions and files |
| Exports | PDF, HTML, source and ZIP; Doc → DOCX, Sheet → XLSX, Slides → PPTX; original attachment downloads for files |
| Shared design kits | Workspace font and color tokens, captured in each saved version |
| Agent connections | MCP over Streamable HTTP, OAuth and revocable personal tokens |
| Workspace boundaries | Each account owns one workspace; private operations are workspace-scoped |

The interface follows the Kilat design system, with a light, dark or system theme switch in the top bar. Geist and Geist Mono ship inside the image, so the app itself loads no third-party fonts or scripts (artifacts may; see Security). Published artifacts use their captured design tokens instead of the interface theme.

The JSON schemas in `config/artifact_types/{doc,sheet,slides}.json` are the portable contract shared with Kilat Web. Typed content is validated and stored as canonical JSON; rendering and Office downloads run locally, without AWS or a rendering service. PDF downloads use Chromium. Office files are generated as OOXML with rubyzip, with no additional runtime dependency. Sheets include one worksheet per tab, column formats and real formulas with cached results; row 1 contains column titles and row 2 is the first data row. Formulas support SUM, AVERAGE, IF, ROUND, MIN, MAX, COUNT, VLOOKUP and arithmetic within a tab. Formula errors display as `#ERROR!` in the viewer and Excel error values in XLSX.

### What it does not do

- No automatic import or synchronization of Claude Artifacts, ChatGPT Canvas, Gemini Canvas or Manus workspaces. Agents must explicitly use this server's tools.
- No built-in AI chat or required model API key. Your AI client supplies the intelligence and pays its own model costs.
- No autosave, real-time co-editing, arbitrary website visual editor or server-side execution of artifact code.
- No live Markdown preview while typing, inline document attachments, team invitations or billing.
- Design kits currently contain fonts and colors, not a full component/template system. Freeform HTML can override those styles; consistent agent output is not guaranteed by tokens alone.
- Generic file artifacts are stored and downloaded, not converted into editable documents. Their link shows a download page; Markdown, HTML and rich-text links render the page.

## Quick start

Use a Linux host (x86_64 or ARM64) with Git, Docker Engine and Docker Compose v2. No host Ruby or Node installation is required.

```sh
git clone --branch v1.0.0 https://github.com/KilatHost/artifact.git
cd artifact
cp .env.example .env
chmod 600 .env
openssl rand -hex 64
openssl rand -hex 64
```

Put the two independently generated values in `.env` as `SECRET_KEY_BASE` and `POSTGRES_PASSWORD`. Keep the database password hexadecimal because Compose interpolates it into a URL.

```sh
docker compose pull
docker compose up -d --wait
curl --fail http://localhost:3000/up
```

`docker compose pull` downloads the release image `ghcr.io/kilathost/artifact` at the `ARTIFACT_VERSION` in `.env`. To build the image from your checkout instead, run `docker compose up -d --build --wait`. Releases and their changes are listed in [CHANGELOG.md](CHANGELOG.md).

Open <http://localhost:3000> and create an account. There is no default account or seeded password. The port binds to the host's loopback interface, not the public network.

Compose runs three services: `web` (Rails behind Thruster), `jobs` (purges artifacts deleted more than 7 days ago, hourly) and `db` (PostgreSQL). Without Compose, schedule `bin/rails artifacts:purge_archived`.

**Forgotten password.** The self-hosted edition sends no email. An operator runs `docker compose exec web bin/rails users:reset_password EMAIL=person@example.com`, which prints a new random password once and revokes that account's OAuth connections.

For remote access, TLS, storage, backups, restores and upgrades, follow **[deploy.md](deploy.md)**.

## How publishing works

1. Create a private artifact and save versions as you work.
2. Make it public. Its link is `/p/<public_id>`, with a Kilat bar (title, download, copy link) above the artifact.
3. By default every saved version, including a restore, is live at once. With `KILAT_PUBLIC_LINKS=pinned`, publishing pins the current version until an explicit update. Make it private again to turn the link off; the owner can still open it there.

Unpublishing disables the public endpoint, but cannot recall copies already downloaded, cached by third parties or captured in screenshots. Public access is read-only; private version history is not published.

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

Authorization codes require S256 PKCE. Registered redirects must use HTTPS, except supported HTTP loopback redirects. Client registration can request a space-separated `scope`; omitted scope defaults to `read write`. Revoke grants from **Connections**.

Tested: Claude, as a custom connector on claude.ai over OAuth (November 2026): sign-in, create, read, update, publish, Markdown briefs and interactive HTML decks. Not yet tested: ChatGPT, Gemini and Manus; their plans and connector capabilities may differ.

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

### v1 MCP contract

OAuth defaults and the personal-token form select `read write`; `publish` is always opt-in. Scopes remain independent. Each connection acts within its owner's workspace.

| Tool | Scope | Important inputs |
| --- | --- | --- |
| `list_artifacts` | `read` | Optional `offset`; 100 results per page |
| `get_artifact` | `read` | Artifact `id`; optional `version` number |
| `create_artifact` | `write` | `request_id`, `title`, `kind`, `content`; optional `design_kit_id` |
| `update_artifact` | `write` | `id`, `content`, `expected_version`; optional `title`, `kind`, `request_id` |
| `artifact_history` | `read` | `id`; optional `offset`; 100 results per page |
| `restore_artifact` | `write` | `id`, `version`, `expected_version`; optional `request_id` |
| `delete_artifact` | `write` | `id`; restorable in the web app for 7 days |
| `list_design_kits` | `read` | Optional `offset`; 100 results per page |
| `create_design_kit` | `write` | `name`, `tokens` |
| `update_design_kit` | `write` | Kit `id`, `name`, `tokens` |
| `publish_artifact` | `publish` | `id` |
| `unpublish_artifact` | `publish` | `id` |

`create_artifact` accepts `markdown` (prose) or `html` (designed or interactive pages). Artifact summaries contain `id,title,kind,design_kit_id,updated_at,version,public,public_version,url,edit_url`. The ID and URL stay stable across revisions. `public_version` is the pin number or null (private or following latest). Lists return arrays, at most 100 items per offset page; history omits content. Get adds `content,latest_version,author,connection,file` (file metadata or null). Tool outputs are JSON encoded in MCP text content.

Get/history expose `author` as a display name and `connection: {type,id,name}` or null for legacy rows. Types are `user`, `api_token`, `oauth_application`; MCP names come from the authenticated token/application, browser names from the user email. Names are captured at write time; revoked connections remain identifiable. Caller-supplied authors are not accepted.

Create requires `request_id` (1–128 characters); update/restore accept it optionally. Reuse it only for identical retries: the workspace-wide receipt includes tool name, authenticated connection type/ID (or null), and inputs. A retry returns the original result without a new version, even after later edits. Different inputs, tools or connections yield `idempotency_mismatch`. Receipts have no expiry; use unique IDs across agents. Without a request ID, revise retries are not idempotent.

Update and restore require `expected_version`, checked under the artifact lock. **Stale-write recovery:** (1) call `get_artifact`; (2) reapply your intended change to its latest content, preserving other edits; (3) retry with `expected_version` set to that version and a new request ID if inputs changed. Do not blindly retry stale content.

Tool errors have `isError:true` and JSON text `{error,message,...}`. Codes: `version_conflict` (includes `current_version` and `recovery` hint), `not_found`, `permission_denied` (includes `required_scope`), `invalid_request`, `idempotency_mismatch`. Invalid/revoked authentication instead returns HTTP 401 `{error:"invalid_token"}` and discovery challenge. Protocol errors remain JSON-RPC errors.

`KILAT_PUBLIC_LINKS=latest` (default/self-host) follows every revision. `pinned` (cloud) pins on publication; revisions never advance a pin. Existing null-pin publications continue following latest. The owner can choose **Update public link** on the artifact page. Calling `publish_artifact` again advances a pin too: opt-in `publish` scope is explicit owner delegation for this action, not just initial publication. Ask the owner before publishing/advancing. Unpublish clears the pin and disables anonymous page/frame/export/file access; public responses use no-store caching.

MCP exposes file metadata, not binary upload/download tools. Browser uploads and authorized HTTP downloads handle files.

#### Launch template: editable HTML report

Give the user the artifact's `url` so they can use **Edit → Page text** in the viewer. Mark only static, text-only elements, using a unique name that starts with a letter and contains at most 64 letters, digits, hyphens or underscores. Preserve markers when an agent revises the report.

```html
<main>
  <h1 data-kilat-editable="report-title">Quarterly report</h1>
  <p data-kilat-editable="report-summary">Summarize the key finding here.</p>
  <figure>
    <div id="chart"></div>
    <figcaption data-kilat-editable="chart-caption">Comparison with the prior quarter.</figcaption>
  </figure>
</main>
```

Page text editing changes only the marked elements' text, not their layout or JavaScript. Use **Source** and **Preview draft** for arbitrary HTML. Markdown has a **Formatted** mode for simple text and a **Source** mode for the full document.

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

The production image omits development/test gems. Run lint, security scans and tests in a development environment, not by assuming those tools exist in that image. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, and [RELEASING.md](RELEASING.md) for how releases are cut.

## Security and operations

Artifact content is untrusted input, not agent instructions. Every response that carries artifact content sends `Content-Security-Policy: sandbox allow-scripts allow-popups …` without `allow-same-origin`, so an artifact runs with an opaque origin: it cannot read this app's cookies, storage or pages, and `connect-src 'none'` blocks fetch and XHR. Set `ARTIFACT_EXTERNAL_RESOURCES=false` to also block the CDN, font and https image hosts (visitors' browsers otherwise contact them when an artifact asks). PDF export runs Chromium without its own sandbox (Docker's default seccomp profile prevents it), with scripts disabled and every request aborted, so a page drawn by scripts (such as a slide deck) prints as its first static state; the PDF download is a static print. HTML artifacts can use forms, dialogs, downloads and the clipboard inside the page, but cannot send data anywhere; opened on its own, an artifact frame redirects to its viewer page. Add network-level egress restrictions for defense in depth.

Public deployments need TLS, trusted proxy configuration, request/upload limits, backups and monitoring. Sign-up is open only for the first account; set `ALLOW_SIGNUP=true` to let anyone create an account (each gets its own workspace). See [deploy.md](deploy.md) for release gates and operational limits.

Report suspected vulnerabilities privately as described in [SECURITY.md](SECURITY.md), not in a public issue; do not publish credentials or a working exploit against customer data.

## License

[Apache License 2.0](LICENSE).

**Trademarks.** The license covers the code, not the Kilat and Kilat Artifact names or the bolt marks (`public/icon.svg`, `public/icon.png`, `app/assets/images/kilat-artifact-mark.svg`). You may run unmodified copies under these names. If you distribute a modified version, use your own name and marks.

Geist and Geist Mono are by Vercel and basement.studio, under the SIL Open Font License 1.1 (`app/assets/fonts/GEIST-OFL.txt`).
