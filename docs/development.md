# Development

Ruby **3.3.13**, Rails **8.1**, PostgreSQL, Hotwire/Stimulus, Trix, native CSS, the MCP Ruby SDK, Doorkeeper, Active Storage and Ferrum/Chromium. No Node build, Redis or vector database is required. Storage can use a local volume or S3-compatible object storage.

## Local setup

With Ruby 3.3.13 and a disposable PostgreSQL database available:

```sh
bundle install
unset PGUSER PGPASSWORD PGHOST DATABASE_URL
export DATABASE_URL=postgresql://localhost/kilat_artifact_development
bin/rails db:prepare
ALLOW_SIGNUP=true bin/rails server -b 127.0.0.1 -p 3000
```

Open <http://localhost:3000/registration/new> to create a local account. On Ubuntu, start PostgreSQL first with `sudo service postgresql start`. Unset inherited PostgreSQL variables before Rails commands; an intentional `DATABASE_URL` below selects the disposable local database. `ALLOW_SIGNUP=true` keeps registration open for workspace-boundary testing.

## Tests and lint

PDF export also needs Chromium; set `BROWSER_PATH` when it is not discoverable. Never point test commands at a development or production database:

```sh
unset PGUSER PGPASSWORD PGHOST DATABASE_URL
export DATABASE_URL=postgresql://localhost/kilat_artifact_test
RAILS_ENV=test bin/rails db:prepare
PARALLEL_WORKERS=1 bin/rails test
bundle exec rubocop
bundle exec brakeman --no-pager --quiet
bin/rails zeitwerk:check
```

The production image omits development/test gems. Run lint, security scans and tests in a development environment, not by assuming those tools exist in that image. See [CONTRIBUTING.md](../CONTRIBUTING.md) before opening a pull request, and [RELEASING.md](../RELEASING.md) for how releases are cut.


## Compose smoke test

In a scratch checkout on Linux with Docker (the smoke test deletes its own Compose volumes):

```sh
docker compose build
script/smoke.sh
```

This covers signup, publish, PDF, file round trip, oversized upload rejection, restart, backup/restore and purge. It contains its own copies of the deployment commands; it does not parse `deploy.md`. Keep both in sync when changing operations.

[Documentation index](README.md)
