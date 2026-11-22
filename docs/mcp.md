# Connecting agents with MCP

Endpoint: `https://your-host.example/mcp`.

Transport: **stateless MCP Streamable HTTP**, with JSON responses. No stdio endpoint is provided.

## OAuth

For compatible remote MCP clients, enter the endpoint URL and complete browser authorization. The server exposes:

| Endpoint | Purpose |
| --- | --- |
| `/.well-known/oauth-authorization-server` | Authorization-server discovery |
| `/.well-known/oauth-protected-resource` | Protected-resource discovery (also available at the MCP-specific path) |
| `/.well-known/oauth-protected-resource/mcp` | Protected-resource discovery |
| `/oauth/register` | Dynamic public-client registration |
| `/oauth/authorize` | Owner consent |
| `/oauth/token` | Authorization-code exchange and refresh |
| `/oauth/revoke` | Token revocation |

Authorization codes require S256 PKCE. Registered redirects must use HTTPS, except supported HTTP loopback redirects. Client registration can request a space-separated `scope`; omitted scope defaults to `read write`. Revoke grants from **Connections**.

Tested over OAuth (November 2026):

| Client | Verified |
| --- | --- |
| Claude, custom connector on claude.ai | Sign-in, create, read, update, publish, Markdown briefs and interactive HTML decks |
| MCP Inspector 2.16.0 | Sign-in and create a private artifact |
| MCPorter 0.17.1 | Sign-in; read an owner's browser edit and revise it at the same URL; stale writes return `version_conflict`; revoking the connection forces new consent |
| Claude Code 2.1.330 (remote HTTP) | Sign-in and connection only; tool calls from the model were not exercised |

Inspector, MCPorter and Claude Code were tested against a local HTTPS endpoint. Not yet tested: Codex CLI, ChatGPT, Gemini and Manus; their plans and connector capabilities may differ.

## Personal tokens

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

## v1 MCP contract

OAuth defaults and the personal-token form select `read write`; `publish` is always opt-in. Scopes remain independent. Each connection acts within its owner's workspace.

| Tool | Scope | Important inputs |
| --- | --- | --- |
| `get_artifact_schema` | `read` | `kind`: `doc`, `sheet` or `slides` |
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

`create_artifact` accepts `markdown` (prose), `html` (designed or interactive pages), and `doc`, `sheet`, `slides` (structured JSON strings matching `get_artifact_schema`). Artifact summaries contain `id,title,kind,design_kit_id,updated_at,version,public,public_version,url,edit_url`. The ID and URL stay stable across revisions. `public_version` is the pin number or null (private or following latest). Lists return arrays, at most 100 items per offset page; history omits content. Get adds `content,latest_version,author,connection,file` (file metadata or null). Tool outputs are JSON encoded in MCP text content.

Get/history expose `author` as a display name and `connection: {type,id,name}` or null for legacy rows. Types are `user`, `api_token`, `oauth_application`; MCP names come from the authenticated token/application, browser names from the user email. Names are captured at write time; revoked connections remain identifiable. Caller-supplied authors are not accepted.

Create requires `request_id` (1–128 characters); update/restore accept it optionally. Reuse it only for identical retries: the workspace-wide receipt includes tool name, authenticated connection type/ID (or null), and inputs. A retry returns the original result without a new version, even after later edits. Different inputs, tools or connections yield `idempotency_mismatch`. Receipts have no expiry; use unique IDs across agents. Without a request ID, revise retries are not idempotent.

Update and restore require `expected_version`, checked under the artifact lock. **Stale-write recovery:** (1) call `get_artifact`; (2) reapply your intended change to its latest content, preserving other edits; (3) retry with `expected_version` set to that version and a new request ID if inputs changed. Do not blindly retry stale content.

Tool errors have `isError:true` and JSON text `{error,message,...}`. Codes: `version_conflict` (includes `current_version` and `recovery` hint), `not_found`, `permission_denied` (includes `required_scope`), `invalid_request`, `idempotency_mismatch`. Invalid/revoked authentication instead returns HTTP 401 `{error:"invalid_token"}` and discovery challenge. Protocol errors remain JSON-RPC errors.

`KILAT_PUBLIC_LINKS=latest` (default/self-host) follows every revision. `pinned` (cloud) pins on publication; revisions never advance a pin. Existing null-pin publications continue following latest. The owner can choose **Update public link** on the artifact page. Calling `publish_artifact` again advances a pin too: opt-in `publish` scope is explicit owner delegation for this action, not just initial publication. Ask the owner before publishing/advancing. Unpublish clears the pin and disables anonymous page/frame/export/file access; public responses use no-store caching.

MCP exposes file metadata, not binary upload/download tools. Browser uploads and authorized HTTP downloads handle files.

## Launch template: editable HTML report

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


## Input reference

IDs, version numbers and `expected_version` are integers ≥ 1; offsets are integers ≥ 0 and default to 0. Unknown input properties are rejected. All inputs in the tool table are required unless marked optional. `tokens` accepts only `font`, `background`, `foreground`, `accent`; see [Design kits](design-kits.md). `content` is a string, including for typed JSON. Update replaces the complete content, not a patch.

The route accepts GET, POST and DELETE at `/mcp`; use a Streamable HTTP client, not a browser page or a legacy SSE transport. The contract is defined in [ArtifactMcp](../app/services/artifact_mcp.rb) and [authentication routes](../config/routes/auth.rb).

[Documentation index](README.md) · [Troubleshooting](troubleshooting.md)
