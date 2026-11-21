# Changelog

All notable changes to Kilat Artifact are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/). The MCP tool contract in the README
is part of the public API: breaking it requires a new major version.

## [1.0.0] - 2026-11-21

First tagged open-source release.

### Added

- Artifacts in Markdown, HTML, rich text, Doc, Sheet and Slides (structured JSON) and uploaded files up to 20 MiB.
- Immutable version history with restore, and stale-write detection for browser and MCP edits.
- Direct in-page editing: formatted and source modes for Markdown, page-text editing of marked HTML blocks, source and draft preview for any HTML.
- Private-by-default artifacts with public links that follow the latest version, or pin a version with `KILAT_PUBLIC_LINKS=pinned`.
- Delete with a 7-day restore window, then scheduled purge by the `jobs` service.
- Exports to PDF (Chromium in the container), HTML, source and ZIP; Doc to DOCX, Sheet to XLSX and Slides to PPTX, rendered locally.
- Workspace design kits (font and color tokens) captured in each saved version.
- MCP over stateless Streamable HTTP with OAuth 2.1 (dynamic registration, S256 PKCE, refresh, revocation) and revocable personal tokens with independent `read`, `write` and `publish` scopes.
- v1 MCP contract: idempotent `request_id` retries, required `expected_version` on revise and restore, and per-connection authorship in history.
- Sandboxed rendering of untrusted artifact content with an opaque origin and no network access from the page.
- Single-host Docker Compose deployment with PostgreSQL 17, and an operator password reset task.
- Versioned multi-arch (`linux/amd64`, `linux/arm64`) images at `ghcr.io/kilathost/artifact`, with a source archive and SHA-256 checksums on each GitHub release.
- Upgrade, backup and restore procedures in `deploy.md`, a contribution guide and a private security reporting policy.

### Fixed

- DOCX, XLSX and PPTX downloads no longer carry unneeded ZIP64 headers, so LibreOffice opens them without reporting corruption ([#7](https://github.com/KilatHost/artifact/pull/7)).
- **Connections** shows the scopes the owner actually granted to an OAuth client, not every scope the client registered for; authorization is unchanged ([#8](https://github.com/KilatHost/artifact/pull/8)).

### Known limitations

- S3-compatible storage is configurable but not yet verified.
- Only the AI clients and auth paths listed as tested in the README are claimed to work.
- No email delivery, team invitations, quotas or billing.

[1.0.0]: https://github.com/KilatHost/artifact/releases/tag/v1.0.0
