# Contributing to Kilat Artifact

Thanks for helping. Bug reports, documentation fixes and focused pull requests
are welcome. For security problems, follow [SECURITY.md](SECURITY.md) instead
of opening an issue.

## Before you start

- Search existing issues and pull requests first.
- Open an issue before a large change, a new dependency or a change to the MCP
  tool contract, so the approach can be agreed before you write it.
- Features listed under *What it does not do* in the README are out of scope
  for v1 unless an issue says otherwise.

## Development setup

You need Ruby 3.3.13 (see `.ruby-version`), PostgreSQL and, for PDF export,
Chromium (set `BROWSER_PATH` if it is not found). No Node build or Redis is
used.

```sh
bundle install
export DATABASE_URL=postgresql://localhost/kilat_artifact_development
bin/rails db:prepare
ALLOW_SIGNUP=true bin/rails server
```

Sign-up closes after the first account; `ALLOW_SIGNUP=true` lets you create
more accounts to test workspace boundaries. If your shell sets `PGHOST`,
`PGUSER` or `PGPASSWORD` for another database, unset them first.

## Checks

Run these against a disposable test database before you open a pull request.
CI runs the same commands, plus a Docker Compose smoke check.

```sh
export DATABASE_URL=postgresql://localhost/kilat_artifact_test
RAILS_ENV=test bin/rails db:prepare
PARALLEL_WORKERS=1 bin/rails test
bundle exec rubocop
bundle exec brakeman --no-pager --quiet
bin/rails zeitwerk:check
```

Changes to the Dockerfile, `compose.yaml`, the entrypoint or backup and
restore behavior should also pass the end-to-end check on a Linux host with
Docker (it builds the image and deletes its own Compose volumes, so run it in
a scratch checkout):

```sh
docker compose build
script/smoke.sh
```

## Pull requests

- Keep each pull request to one change, with tests for new behavior and bug fixes.
- Follow the existing style; RuboCop enforces the Rails Omakase rules.
- Update the README or `deploy.md` when behavior, configuration or operations change.
- Add a line to the topmost section of [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
- MCP tools, inputs, outputs and error codes in the README's *v1 MCP contract* are
  a public API. Additive changes are fine; breaking changes need a new major version.
- Database migrations must work on an existing install through the entrypoint's
  `db:prepare`. Say in the pull request if a migration cannot be rolled back.
- Never commit secrets, `.env` files, database dumps or uploaded files.

## License and names

By contributing, you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), as described in section 5 of the license. The
license does not cover the Kilat names and marks; see *Trademarks* in the README.
