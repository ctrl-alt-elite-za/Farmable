#!/usr/bin/env bash
set -euo pipefail
: "${BACKUP_BUCKET:?BACKUP_BUCKET is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

file="/tmp/farmable-${COMMIT_SHA}.dump"
trap 'rm -f "$file" .env compose.yaml compose.staging.yaml' EXIT
curl -fsSL "https://raw.githubusercontent.com/ctrl-alt-elite-za/Farmable/${COMMIT_SHA}/compose.yaml" -o compose.yaml
curl -fsSL "https://raw.githubusercontent.com/ctrl-alt-elite-za/Farmable/${COMMIT_SHA}/infra/compose.staging.yaml" -o compose.staging.yaml
DATABASE_URL="$(aws ssm get-parameter --name /farmable/staging/database-url --with-decryption --query Parameter.Value --output text)"
POSTGRES_PASSWORD="$(aws ssm get-parameter --name /farmable/staging/postgres-password --with-decryption --query Parameter.Value --output text)"
printf 'DATABASE_URL=%s\nPOSTGRES_USER=farmable\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=farmable\n' "$DATABASE_URL" "$POSTGRES_PASSWORD" > .env
if ! docker compose --env-file .env -f compose.yaml -f compose.staging.yaml ps -q database | grep -q .; then
  echo 'No staging database is running yet; there is nothing to back up.'
  exit 0
fi
docker compose --env-file .env -f compose.yaml -f compose.staging.yaml exec -T database \
  pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$file"
aws s3 cp "$file" "s3://${BACKUP_BUCKET}/staging/${COMMIT_SHA}.dump" --sse AES256
