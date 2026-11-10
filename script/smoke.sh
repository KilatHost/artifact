#!/usr/bin/env bash
# End-to-end check of a Compose install on Linux: signup, create, publish,
# PDF in the container, upload, restart, backup and restore.
set -euo pipefail
BASE=http://localhost:3000
WORK=$(mktemp -d)
JAR=$WORK/cookies
PROJECT=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
VOLUME=${PROJECT}_artifact_storage
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n== %s\n' "$*"; }
wait_up() { for _ in $(seq 1 60); do curl -fsS "$BASE/up" >/dev/null 2>&1 && return 0; sleep 2; done; echo "app did not start"; return 1; }
# The page-wide token from <meta name="csrf-token">; form tokens are scoped to their own form.
meta_token() { grep -o 'name="csrf-token" content="[^"]*"' | head -1 | sed 's/.*content="//;s/"$//'; }
token() { curl -fsS -b "$JAR" -c "$JAR" "$BASE$1" | meta_token; }
location() { grep -i '^location:' | tr -d '\r' | awk '{print $2}'; }

step "Start"
docker compose up -d
wait_up

step "Sign up"
T=$(token /registration/new)
curl -fsS -b "$JAR" -c "$JAR" -o /dev/null --data-urlencode "authenticity_token=$T" \
  --data-urlencode "user[email]=smoke@example.test" --data-urlencode "user[password]=smoke-password-123" \
  --data-urlencode "user[password_confirmation]=smoke-password-123" "$BASE/registration"

step "Create a document"
T=$(token /artifacts/new)
DOC=$(curl -sS -b "$JAR" -c "$JAR" -D - -o /dev/null --data-urlencode "authenticity_token=$T" \
  --data-urlencode "artifact[title]=Smoke brief" --data-urlencode "artifact[kind]=document" \
  --data-urlencode "artifact[content]=<h1>Smoke check passed</h1><script>alert(1)</script>" "$BASE/artifacts" | location)
DOC_PATH=${DOC#"$BASE"}
echo "$DOC_PATH"

step "Publish"
PAGE=$(curl -fsS -b "$JAR" -c "$JAR" "$BASE$DOC_PATH")
VERSION=$(echo "$PAGE" | grep -o 'name="version_id" value="[0-9]*"' | head -1 | grep -o '[0-9]*')
T=$(echo "$PAGE" | meta_token)
curl -fsS -b "$JAR" -c "$JAR" -o /dev/null --data-urlencode "authenticity_token=$T" -d "version_id=$VERSION" "$BASE$DOC_PATH/publish"
PUBLIC=$(curl -fsS -b "$JAR" "$BASE$DOC_PATH" | grep -o '/p/[A-Za-z0-9]*' | head -1)
curl -fsS "$BASE$PUBLIC" | grep -q "Smoke check passed"
if curl -fsS "$BASE$PUBLIC" | grep -q "<script>alert"; then echo "script survived sanitizing"; exit 1; fi
echo "public $PUBLIC ok"

step "PDF export inside the container"
curl -fsS -b "$JAR" -o "$WORK/doc.pdf" "$BASE$DOC_PATH/export?export_format=pdf"
head -c 4 "$WORK/doc.pdf" | grep -q '%PDF'
echo "pdf $(wc -c < "$WORK/doc.pdf") bytes"

step "Upload a file"
head -c 2000000 /dev/urandom > "$WORK/upload.bin"
T=$(token /artifacts/new)
FILE=$(curl -sS -b "$JAR" -c "$JAR" -D - -o /dev/null -F "authenticity_token=$T" -F "artifact[title]=Smoke file" \
  -F "artifact[kind]=file" -F "artifact[content]=" -F "artifact[file]=@$WORK/upload.bin" "$BASE/artifacts" | location)
FILE_PATH=${FILE#"$BASE"}
curl -fsS -b "$JAR" -o "$WORK/download.bin" "$BASE$FILE_PATH/export?export_format=file"
cmp "$WORK/upload.bin" "$WORK/download.bin"
echo "file round trip ok"

step "Oversized upload is refused"
head -c 24000000 /dev/zero > "$WORK/big.bin"
CODE=$(curl -sS -b "$JAR" -o /dev/null -w '%{http_code}' -F "artifact[file]=@$WORK/big.bin" "$BASE/artifacts" || true)
echo "status $CODE"
[ "$CODE" = "413" ]

check_data() {
  curl -fsS "$BASE$PUBLIC" | grep -q "Smoke check passed"
  curl -fsS -b "$JAR" -o "$WORK/again.bin" "$BASE$FILE_PATH/export?export_format=file"
  cmp "$WORK/upload.bin" "$WORK/again.bin"
}

step "Restart keeps data"
docker compose restart web
wait_up
check_data
echo "restart ok"

step "Back up"
docker compose exec -T db pg_dump -U kilat -Fc kilat_artifact_production > "$WORK/db.dump"
docker run --rm -v "$VOLUME":/data -v "$WORK":/backup alpine tar czf /backup/storage.tgz -C /data .
ls -l "$WORK/db.dump" "$WORK/storage.tgz"

step "Destroy and restore"
docker compose down -v
docker compose up -d db
for _ in $(seq 1 30); do docker compose exec -T db pg_isready -U kilat >/dev/null 2>&1 && break; sleep 2; done
docker compose exec -T db pg_restore -U kilat -d kilat_artifact_production --clean --if-exists --no-owner < "$WORK/db.dump"
docker volume create "$VOLUME" >/dev/null
docker run --rm -v "$VOLUME":/data -v "$WORK":/backup alpine tar xzf /backup/storage.tgz -C /data
docker run --rm -v "$VOLUME":/data alpine chown -R 1000:1000 /data
docker compose up -d
wait_up
check_data
echo "restore ok"

step "Purge job runs"
docker compose exec -T web bin/rails artifacts:purge_archived

printf '\nSmoke check passed.\n'
